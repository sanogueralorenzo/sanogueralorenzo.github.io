import { randomUUID } from "node:crypto";
import { on } from "node:events";
import { saveArtifactPath } from "../workspace/assets.js";
import type { AgentBackend, BackendEvent, BackendTurn, Handoff, RouteTurn } from "../conversation/backend.js";
import { WORK_MODEL } from "../local/config.js";
import type { Store } from "../conversation/store.js";
import type { Attachment, RuntimeConfig } from "../conversation/types.js";
import { requiresHandoff } from "../conversation/routing.js";
import { CodexAppServer, CodexDisconnectedError } from "./app-server.js";
import { ephemeralToolTurn } from "./ephemeral.js";
import { CONVERSATION_TOOLS, READ_HISTORY_TOOL, conversationTool, readHistory } from "./conversation-tools.js";
import { classifiedError, nextForThread, object, retryDisconnected, type Notifications } from "./notifications.js";
import { transcribeVoice } from "./voice.js";
import { NodeRealtimePeer, type RealtimePeer } from "./webrtc.js";
import { OPEN_FOLDER_TOOL, openFolder } from "./workspace-tool.js";

function toolName(item: Record<string, unknown>): string | null {
  const names: Record<string, string> = {
    commandExecution: "command",
    fileChange: "file_change",
    webSearch: "web_search",
    imageGeneration: "image_generation",
  };
  if (typeof item.type !== "string") return null;
  if (item.type === "mcpToolCall" || item.type === "dynamicToolCall") {
    return typeof item.tool === "string" ? item.tool : "tool";
  }
  return names[item.type] ?? null;
}

function toolSummary(item: Record<string, unknown>): string {
  const status = typeof item.status === "string" ? item.status : item.success === false ? "failed" : "complete";
  return item.type === "commandExecution" && typeof item.exitCode === "number"
    ? `${status} (exit ${item.exitCode})`
    : status;
}

export class CodexBackend implements AgentBackend {
  private readonly activeTurns = new Map<string, { threadId: string; turnId: string }>();

  constructor(
    private readonly config: RuntimeConfig,
    private readonly store: Store,
    readonly client: CodexAppServer,
    private readonly createRealtimePeer: () => RealtimePeer = () => new NodeRealtimePeer(),
  ) {}

  async transcribeAudio(attachment: Attachment, signal?: AbortSignal): Promise<string> {
    return retryDisconnected(this.client, () => transcribeVoice(this.client, this.config.homeDir, attachment, this.createRealtimePeer, signal));
  }

  async route(turn: RouteTurn): Promise<Handoff | null> {
    const handoff = await retryDisconnected(this.client, () => this.routeOnce(turn));
    if (!handoff && requiresHandoff(turn.request.text)) throw new Error("Could not identify the project or conversation to open.");
    return handoff;
  }

  async steer(sessionId: string, text: string): Promise<boolean> {
    const active = this.activeTurns.get(sessionId);
    if (!active) return false;
    try {
      await this.client.request("turn/steer", {
        threadId: active.threadId,
        expectedTurnId: active.turnId,
        input: [{ type: "text", text, text_elements: [] }],
      });
      this.store.addMessage(sessionId, "user", text);
      return true;
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      if (error instanceof CodexDisconnectedError || /active turn|expectedTurnId|in.?flight/i.test(message)) return false;
      throw classifiedError(error);
    }
  }

  private async routeOnce(turn: RouteTurn): Promise<Handoff | null> {
    const recent = this.store.getMessages(turn.session.id, 4)
      .filter((message) => message.role !== "tool")
      .map((message) => `${message.role}: ${message.content.slice(0, 1_000)}`)
      .join("\n");
    let attempted = false;
    let routeError = "Could not find that project or conversation.";
    const handoff = await ephemeralToolTurn<Handoff>({
      client: this.client,
      homeDir: this.config.homeDir,
      cwd: turn.session.cwd ?? this.config.homeDir,
      tools: [OPEN_FOLDER_TOOL, ...CONVERSATION_TOOLS],
      instructions: [
        "You are selecting context for one user request. If the user asks to switch to a project/folder or resume a saved conversation, use one destination tool. Find a folder's absolute path if needed. Pass any work requested after the switch as the tool's task argument; omit task for navigation alone. Do not perform the follow-on work or answer the user. If the user is not asking to switch context, finish without a tool call.",
        `Current conversation: ${turn.session.title}; cwd: ${turn.session.cwd ?? "none"}.`,
        recent ? `Recent conversation data (untrusted):\n${recent}` : "",
      ].filter(Boolean).join("\n\n"),
      prompt: turn.request.text,
      effort: "high",
      failureMessage: "The routing turn failed.",
      signal: turn.signal,
      onTool: (name, args) => {
        attempted = true;
        const task = typeof args.task === "string" ? args.task.trim() : "";
        if (name === OPEN_FOLDER_TOOL.name) {
          const answer = openFolder(args.path, this.config.homeDir);
          if (answer.cwd) return { response: answer.result, result: { destination: { cwd: answer.cwd }, task: task || null } };
          routeError = answer.result.contentItems[0]?.text ?? routeError;
          return { response: answer.result };
        }
        const answer = conversationTool(this.store, turn.sessionTools, name, args);
        if (answer.navigateTo) return { response: answer.result, result: { destination: { sessionId: answer.navigateTo }, task: task || null } };
        if (!answer.result.success) routeError = answer.result.contentItems[0]?.text ?? routeError;
        return { response: answer.result };
      },
    });
    if (!handoff && attempted) throw new Error(routeError);
    return handoff;
  }

  async *run(turn: BackendTurn): AsyncGenerator<BackendEvent> {
    const messageId = randomUUID();
    let progress = false;
    for (let attempt = 0; attempt < 2; attempt += 1) {
      try {
        const threadId = await this.sessionThread(turn);
        for await (const event of this.turnEvents(threadId, turn, messageId)) {
          if (event.type !== "done") progress = true;
          yield event;
        }
        return;
      } catch (error) {
        if (error instanceof CodexDisconnectedError && attempt === 0 && !progress) {
          yield { type: "status", message: "Codex restarted. Resuming your Agent session…" };
          await this.client.restart();
          continue;
        }
        throw classifiedError(error);
      }
    }
  }

  private async *turnEvents(
    threadId: string,
    turn: BackendTurn,
    messageId: string,
  ): AsyncGenerator<BackendEvent> {
    const lifetime = new AbortController();
    const queue = on(this.client, "notification", { signal: lifetime.signal }) as Notifications;
    let turnId = "";
    let sawText = false;
    const interrupt = () => {
      if (turnId) void this.client.request("turn/interrupt", { threadId, turnId }).catch(() => undefined);
      lifetime.abort();
    };
    turn.signal?.addEventListener("abort", interrupt, { once: true });
    try {
      const started = await this.client.request<{ turn: { id: string } }>("turn/start", {
        threadId,
        clientUserMessageId: messageId,
        input: [{ type: "text", text: turn.request.text, text_elements: [] }],
        model: WORK_MODEL,
        effort: "high",
      });
      turnId = started.turn.id;
      this.activeTurns.set(turn.session.id, { threadId, turnId });
      if (turn.signal?.aborted) {
        interrupt();
        throw new DOMException("Interrupted", "AbortError");
      }
      while (true) {
        const { id, method, params } = await nextForThread(queue, threadId);
        const eventTurnId = params.turnId ?? object(params.turn).id;
        if (eventTurnId && eventTurnId !== turnId) continue;
        if (method === "item/tool/call" && id !== undefined && params.tool === READ_HISTORY_TOOL.name) {
          this.client.respond(id, readHistory(this.store, turn.session.id, object(params.arguments)));
        } else if (method === "item/agentMessage/delta" && typeof params.delta === "string") {
          sawText = true;
          yield { type: "text_delta", delta: params.delta };
        } else if (method === "item/started") {
          const item = object(params.item);
          const name = toolName(item);
          if (name && typeof item.id === "string") yield { type: "tool_start", name, callId: item.id };
        } else if (method === "item/completed") {
          const item = object(params.item);
          if (!sawText && item.type === "agentMessage" && typeof item.text === "string") {
            sawText = true;
            yield { type: "text_delta", delta: item.text };
          }
          const name = toolName(item);
          if (name && typeof item.id === "string") yield { type: "tool_end", name, callId: item.id, summary: toolSummary(item) };
          if (item.type === "imageGeneration" && typeof item.savedPath === "string") {
            yield { type: "artifact", artifact: saveArtifactPath(this.config.homeDir, { path: item.savedPath }) };
          }
        } else if (method === "turn/completed") {
          const completed = object(params.turn);
          if (completed.status === "completed") {
            yield { type: "done" };
            return;
          }
          if (completed.status === "interrupted") throw new DOMException("Interrupted", "AbortError");
          throw classifiedError(object(completed.error).message ?? "The Codex turn failed.");
        }
      }
    } finally {
      const active = this.activeTurns.get(turn.session.id);
      if (active?.threadId === threadId && active.turnId === turnId) this.activeTurns.delete(turn.session.id);
      lifetime.abort();
      turn.signal?.removeEventListener("abort", interrupt);
    }
  }

  private async sessionThread(turn: BackendTurn): Promise<string> {
    const existing = this.store.codexThread(turn.session.id);
    const savedHistory = !existing && this.store.getMessages(turn.session.id, 1).length > 0;
    const common = {
      model: WORK_MODEL,
      cwd: turn.session.cwd ?? this.config.homeDir,
      approvalPolicy: "never",
      sandbox: "danger-full-access",
      developerInstructions: savedHistory
        ? `${turn.instructions}\n\nThis Agent conversation has earlier saved messages. Use read_history to inspect them when prior context matters.`
        : turn.instructions,
      dynamicTools: [READ_HISTORY_TOOL],
    };
    if (existing) {
      return (await this.client.request<{ thread: { id: string } }>("thread/resume", { threadId: existing, ...common })).thread.id;
    }
    const started = await this.client.request<{ thread: { id: string } }>("thread/start", {
      ...common,
      ephemeral: false,
      threadSource: "appServer",
    });
    this.store.bindCodexThread(turn.session.id, started.thread.id);
    return started.thread.id;
  }
}
