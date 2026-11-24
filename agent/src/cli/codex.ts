import { createHash, randomUUID } from "node:crypto";
import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import type { ImageContent, JsonObject, Message, TextContent, Tool, ToolCall, ToolResultMessage } from "@earendil-works/pi-ai";
import { startCli } from "./process.ts";
import type { CliUsage, Turn } from "./turn.ts";

type Request = Omit<Turn, "cwd" | "transcript" | "images"> & {
  sessionId?: string;
  messages: Message[];
  tools: Tool[];
};

type Reply = { text: string; calls: ToolCall[]; id?: string; usage?: CliUsage };

type PendingCall = { requestId: number | string; callId: string };
type Process = {
  cli: ReturnType<typeof startCli>;
  events: ReturnType<ReturnType<typeof startCli>["events"]>;
  directory: string;
  settings: string;
  call?: PendingCall;
  idle?: NodeJS.Timeout;
  closing?: Promise<void>;
  thread?: string;
  sources: unknown[];
};

const imageUrl = (image: ImageContent) => `data:${image.mimeType};base64,${image.data}`;
const inputContent = (content: string | (TextContent | ImageContent)[]) => (
  typeof content === "string" ? [{ type: "input_text", text: content }]
    : content.map(part => part.type === "text" ? { type: "input_text", text: part.text } : { type: "input_image", image_url: imageUrl(part) })
);

function history(messages: Message[]) {
  const items: object[] = [];
  const results = new Set(messages.flatMap(message => message.role === "toolResult" ? [message.toolCallId] : []));
  const replayed = new Map<string, string>();
  for (const message of messages) {
    if (message.role === "user") {
      items.push({ type: "message", role: "user", content: inputContent(message.content) });
    } else if (message.role === "assistant") {
      for (const part of message.content) {
        if (part.type === "text" && part.text) {
          items.push({ type: "message", role: "assistant", content: [{ type: "output_text", text: part.text }] });
        } else if (part.type === "toolCall" && results.has(part.id)) {
          const id = `call_agent_${createHash("sha256").update(part.id).digest("hex").slice(0, 24)}`;
          replayed.set(part.id, id);
          items.push({ type: "function_call", name: part.name, call_id: id, arguments: JSON.stringify(part.arguments) });
        }
      }
    } else if (message.role === "toolResult") {
      const id = replayed.get(message.toolCallId);
      if (id) {
        replayed.delete(message.toolCallId);
        const output = inputContent(message.content);
        if (message.isError) output.unshift({ type: "input_text", text: "Tool failed:" });
        items.push({ type: "function_call_output", call_id: id, output });
      }
    }
  }
  return items;
}

function continuation(messages: Message[], call: PendingCall | undefined): ToolResultMessage | undefined {
  if (!call) return;
  for (let index = messages.length - 1; index >= 0; index--) {
    const message = messages[index];
    if (message.role === "system") continue;
    return message.role === "toolResult" && message.toolCallId === call.callId ? message : undefined;
  }
}

function cliArguments(search: boolean) {
  return ["app-server", "--listen", "stdio://", "-c", "mcp_servers={}", "-c", "agents.enabled=false",
    "-c", "project_doc_max_bytes=0", "-c", `web_search="${search ? "live" : "disabled"}"`,
    "--enable", "code_mode", "--enable", "skip_host_skill_discovery",
    "--disable", "shell_tool", "--disable", "unified_exec", "--disable", "hooks", "--disable", "plugins",
    "--disable", "apps", "--disable", "image_generation", "--disable", "sleep_tool"];
}

export class CodexTurns {
  private readonly processes = new Map<string, Process>();
  private readonly closing = new Set<Promise<void>>();
  private readonly running = new Set<string>();
  private closed = false;

  private stop(key: string, process: Process) {
    if (this.processes.get(key) === process) this.processes.delete(key);
    clearTimeout(process.idle);
    if (process.closing) return process.closing;
    const done = process.cli.stop().finally(() => rm(process.directory, { recursive: true, force: true }).catch(() => {}));
    process.closing = done;
    this.closing.add(done);
    void done.then(() => this.closing.delete(done), () => this.closing.delete(done));
    return done;
  }

  closeSession(id: string) {
    const process = this.processes.get(id);
    if (process) return this.stop(id, process);
  }

  async close() {
    this.closed = true;
    for (const [key, process] of this.processes) void this.stop(key, process);
    await Promise.all(this.closing);
  }

  async run(turn: Request): Promise<Reply> {
    if (this.closed) throw new Error("Codex is shutting down");
    const key = turn.sessionId && !this.running.has(turn.sessionId) ? turn.sessionId : randomUUID();
    this.running.add(key);
    try {
      const settings = JSON.stringify([turn.model, turn.effort, turn.fast, turn.search, turn.instructions, turn.tools]);
      const existing = this.processes.get(key);
      const result = existing?.settings === settings ? continuation(turn.messages, existing.call) : undefined;
      if (existing) {
        if (result) {
          try { return await this.advance(key, existing, turn, result); }
          catch (error) { if (turn.signal.aborted || this.closed) throw error; }
        } else await this.stop(key, existing);
      }

      turn.signal.throwIfAborted();
      return await this.advance(key, await this.start(turn, settings), turn);
    } finally { this.running.delete(key); }
  }

  private async advance(key: string, process: Process, turn: Request, result?: ToolResultMessage): Promise<Reply> {
    this.processes.set(key, process);
    clearTimeout(process.idle);
    const abort = () => { void this.stop(key, process); };
    turn.signal.addEventListener("abort", abort, { once: true });
    try {
      if (this.closed) throw new Error("Codex is shutting down");
      turn.signal.throwIfAborted();
      if (result && process.call) {
        process.cli.send({ id: process.call.requestId, result: { success: !result.isError, contentItems: result.content.map(part =>
          part.type === "text" ? { type: "inputText", text: part.text } : { type: "inputImage", imageUrl: imageUrl(part) }) } });
        process.call = undefined;
      }
      const response = await this.receive(process, turn);
      if (process.call && key === turn.sessionId) {
        process.idle = setTimeout(() => { void this.stop(key, process); }, 120_000).unref();
      } else await this.stop(key, process);
      return response;
    } catch (error) {
      await this.stop(key, process);
      throw error;
    } finally { turn.signal.removeEventListener("abort", abort); }
  }

  private async start(turn: Request, settings: string): Promise<Process> {
    const directory = await mkdtemp(join(tmpdir(), "agent-codex-"));
    try {
      const cli = startCli("codex", cliArguments(turn.search), directory, AbortSignal.timeout(30 * 60_000));
      cli.send({ id: 1, method: "initialize", params: {
        clientInfo: { name: "sanogueralorenzo_agent", title: "Agent", version: "0.1.0" }, capabilities: { experimentalApi: true },
      } });
      return { cli, events: cli.events(), directory, settings, sources: [] };
    } catch (error) {
      await rm(directory, { recursive: true, force: true });
      throw error;
    }
  }

  private async receive(process: Process, turn: Request): Promise<Reply> {
    const { cli, events } = process;
    const send = (id: number, method: string, params: object) => cli.send({ id, method, params });
    const allowed = new Set(turn.tools.map(tool => tool.name));
    let answer = "";
    let id: string | undefined;
    let usage: CliUsage | undefined;
    for (;;) {
      const next = await events.next();
      if (next.done) break;
      const event = next.value;
      const { params } = event;
      if (event.id !== undefined && event.method) {
        if (event.method === "item/tool/call" && params.threadId === process.thread && allowed.has(params.tool)) {
          const actual = params.arguments;
          const valid = actual && typeof actual === "object" && !Array.isArray(actual);
          const nativeCall: ToolCall = { type: "toolCall", id: params.callId, name: params.tool,
            arguments: valid ? actual as JsonObject : {}, ...(!valid && { argumentsError: "Tool arguments must be a JSON object" }) };
          process.call = { requestId: event.id, callId: nativeCall.id };
          return { text: answer, calls: [nativeCall], usage };
        }
        cli.send({ id: event.id, error: { code: -32601, message: "Tool unavailable in Agent" } });
      } else if (event.error) {
        throw new Error("Codex could not start or resume the turn");
      } else if (event.id === 1 && event.result) {
        cli.send({ method: "initialized" });
        send(2, "thread/start", { cwd: process.directory, model: turn.model, modelProvider: "openai", ephemeral: true,
          ...(turn.fast && { serviceTier: "fast" }), approvalPolicy: "never", sandbox: "read-only", environments: [],
          baseInstructions: turn.instructions, experimentalRawEvents: true,
          developerInstructions: turn.tools.length
            ? "The registered Agent tools operate in the role's working directory with the capabilities in their declarations. Use edit or write for file changes when those tools are available to the role. Codex's local sandbox applies to its separate scratch directory."
            : "",
          dynamicTools: turn.tools.map(tool => ({ type: "function", name: tool.name, description: tool.description, inputSchema: tool.parameters, deferLoading: false })) });
      } else if (event.id === 2 && event.result) {
        process.thread = event.result.thread.id;
        send(4, "thread/inject_items", { threadId: process.thread, items: history(turn.messages) });
      } else if (event.id === 4 && event.result) {
        send(3, "turn/start", { threadId: process.thread, input: [], environments: [], ...(turn.effort && { effort: turn.effort }) });
      } else if (params?.threadId === process.thread) {
        if (event.method === "item/agentMessage/delta") turn.progress(params.itemId, params.delta);
        if (event.method === "item/completed" && params.item?.type === "agentMessage" && params.item.phase !== "commentary") {
          answer = params.item.text;
          id = params.item.id;
        }
        if (event.method === "rawResponseItem/completed" && params.item?.role === "assistant") {
          for (const block of params.item.content ?? []) process.sources.push(...(block.annotations ?? []));
        }
        if (event.method === "thread/tokenUsage/updated" && params.tokenUsage?.last) {
          const last = params.tokenUsage.last;
          usage = { input_tokens: last.inputTokens, output_tokens: last.outputTokens, cached_input_tokens: last.cachedInputTokens,
            cache_creation_input_tokens: last.cacheWriteInputTokens, thinking_tokens: last.reasoningOutputTokens, total_tokens: last.totalTokens };
        }
        if (event.method === "turn/completed") {
          if (params.turn.status !== "completed" || !answer.trim()) throw new Error("Codex did not complete the turn");
          for (const source of process.sources) turn.source(source);
          return { text: answer, calls: [], id, usage };
        }
      }
    }
    await cli.result();
    throw new Error("Codex closed before completing the turn");
  }
}
