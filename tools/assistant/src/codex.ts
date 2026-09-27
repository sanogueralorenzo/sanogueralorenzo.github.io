import { spawn, type ChildProcessWithoutNullStreams } from "node:child_process";
import { readFileSync, existsSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import { createInterface } from "node:readline";

type Message = { id?: number; method?: string; params?: Record<string, unknown>; result?: Record<string, unknown>; error?: { message?: string } };
type Listener = (method: string, params: Record<string, unknown>) => void;
type Role = "coordinator" | "session" | "researcher" | "reviewer";
export type ClientTool = { name: string; description: string; inputSchema: Record<string, unknown>;
  execute: (args: Record<string, unknown>) => Promise<string> };
const prompts = new URL("../prompts/", import.meta.url);
const instructions = (role: Role) => ["base", role].map((name) => readFileSync(new URL(`${name}.md`, prompts), "utf8")).join("\n\n");
const input = (text: string) => [{ type: "text", text, text_elements: [] }];
const computerUse = join(process.env.CODEX_HOME || join(homedir(), ".codex"), "computer-use", "Codex Computer Use.app",
  "Contents", "SharedSupport", "SkyComputerUseClient.app", "Contents", "MacOS", "SkyComputerUseClient");

export class CodexService {
  private process?: ChildProcessWithoutNullStreams;
  private ready?: Promise<void>;
  private nextId = 1;
  private pending = new Map<number, { resolve: (value: Record<string, unknown>) => void; reject: (error: Error) => void }>();
  private listeners = new Set<Listener>();
  private completed = new Map<string, Record<string, unknown>>();
  private waiters = new Map<string, { resolve: (value: Record<string, unknown>) => void; reject: (error: Error) => void }>();
  private outputs = new Map<string, string>();
  private directories = new Map<string, string>();
  private loaded = new Set<string>();
  private utilityThreads = new Set<string>();
  private delegations = new Map<string, Set<{ threadId: string; turnId: string }>>();
  private clientTools = new Map<string, Map<string, ClientTool>>();

  subscribe(listener: Listener) { this.listeners.add(listener); return () => this.listeners.delete(listener); }
  private send(message: Message) {
    if (!this.process?.stdin.writable) throw new Error("Codex app-server is unavailable");
    this.process.stdin.write(`${JSON.stringify(message)}\n`);
  }
  private requestRaw(method: string, params: Record<string, unknown> = {}): Promise<Record<string, unknown>> {
    const id = this.nextId++;
    return new Promise((resolve, reject) => {
      this.pending.set(id, { resolve, reject });
      try { this.send({ id, method, params }); }
      catch (error) { this.pending.delete(id); reject(error); }
    });
  }
  async request(method: string, params: Record<string, unknown> = {}) {
    await this.connect();
    return this.requestRaw(method, params);
  }
  private connect(): Promise<void> {
    if (this.ready) return this.ready;
    this.ready = (async () => {
      const args = ["app-server"];
      if (existsSync(computerUse)) args.push("-c", `mcp_servers.computer-use.command=${JSON.stringify(computerUse)}`,
        "-c", 'mcp_servers.computer-use.args=["mcp"]', "-c", "mcp_servers.computer-use.enabled=true");
      const child = spawn("codex", args, { stdio: ["pipe", "pipe", "pipe"] });
      this.process = child;
      child.on("error", (error) => {
        for (const pending of this.pending.values()) pending.reject(error);
        this.pending.clear();
        this.process = undefined;
        this.ready = undefined;
      });
      child.stderr.on("data", (chunk) => process.stderr.write(chunk));
      createInterface({ input: child.stdout }).on("line", (line) => {
        let message: Message;
        try { message = JSON.parse(line) as Message; } catch { return; }
        if (message.id !== undefined && message.method === "item/tool/call") {
          void this.callTool(message.id, message.params || {});
          return;
        }
        if (message.id !== undefined) {
          const pending = this.pending.get(message.id);
          if (!pending) return;
          this.pending.delete(message.id);
          if (message.error) pending.reject(new Error(message.error.message || "Codex request failed"));
          else pending.resolve(message.result || {});
          return;
        }
        if (!message.method) return;
        const params = message.params || {};
        if (message.method === "item/completed") {
          const item = params.item as { type?: string; phase?: string | null; text?: string } | undefined;
          if (item?.type === "agentMessage" && item.text && this.utilityThreads.has(String(params.threadId)) &&
            (item.phase === "final_answer" || item.phase === null))
            this.outputs.set(`${params.threadId}:${params.turnId}`, item.text);
        }
        if (message.method === "turn/completed") {
          const turn = params.turn as { id?: string; status?: string } | undefined;
          if (turn?.id) {
            const key = `${params.threadId}:${turn.id}`;
            if (turn.status === "interrupted" || turn.status === "failed")
              for (const child of this.delegations.get(key) || []) void this.interrupt(child.threadId, child.turnId).catch(() => undefined);
            const waiter = this.waiters.get(key);
            if (waiter) { this.waiters.delete(key); waiter.resolve(params); }
            else this.completed.set(key, params);
          }
        }
        for (const listener of this.listeners) listener(message.method, params);
      });
      child.on("exit", (code) => {
        if (this.process !== child) return;
        const error = new Error(`Codex app-server exited (${code ?? "signal"})`);
        for (const pending of this.pending.values()) pending.reject(error);
        this.pending.clear();
        for (const listener of this.listeners) listener("server/exited", { error: error.message });
        for (const waiter of this.waiters.values()) waiter.reject(error);
        this.waiters.clear();
        this.process = undefined;
        this.ready = undefined;
        this.loaded.clear();
      });
      await this.requestRaw("initialize", { clientInfo: { name: "local_assistant", title: "Assistant", version: "0.1.0" }, capabilities: { experimentalApi: true } });
      this.send({ method: "initialized", params: {} });
    })();
    return this.ready;
  }
  private async thread(role: Role, cwd: string, ephemeral: boolean, sandbox: "read-only" | "danger-full-access", customTools: ClientTool[] = []) {
    const dynamicTools = role === "session" ? [{ type: "function", name: "delegate",
      description: "Ask a separate read-only researcher to investigate or reviewer to critique. Give it a focused task and any context it needs. You own the final answer and all actions.",
      inputSchema: { type: "object", properties: { role: { type: "string", enum: ["researcher", "reviewer"] }, task: { type: "string", minLength: 1 } },
        required: ["role", "task"], additionalProperties: false } }]
      : customTools.map(({ name, description, inputSchema }) => ({ type: "function", name, description, inputSchema }));
    const result = await this.request("thread/start", {
      cwd, model: "gpt-6-luna", serviceTier: "priority", approvalPolicy: "never", sandbox,
      developerInstructions: instructions(role), ephemeral, serviceName: "local_assistant",
      ...(dynamicTools.length && { dynamicTools }),
    });
    const thread = result.thread as { id: string };
    if (!thread?.id) throw new Error("Codex did not return a thread ID");
    this.directories.set(thread.id, cwd);
    this.loaded.add(thread.id);
    if (role !== "session") this.utilityThreads.add(thread.id);
    if (customTools.length) this.clientTools.set(thread.id, new Map(customTools.map((tool) => [tool.name, tool])));
    return thread.id;
  }
  private async callTool(id: number, params: Record<string, unknown>) {
    let worker: string | undefined;
    let parentKey: string | undefined;
    let delegated: { threadId: string; turnId: string } | undefined;
    try {
      const custom = this.clientTools.get(String(params.threadId))?.get(String(params.tool));
      if (custom) {
        const result = await custom.execute((params.arguments || {}) as Record<string, unknown>);
        this.send({ id, result: { contentItems: [{ type: "inputText", text: result }], success: true } });
        return;
      }
      if (params.tool !== "delegate") throw new Error(`Unknown tool: ${params.tool}`);
      const args = params.arguments as { role?: unknown; task?: unknown };
      if (!args || (args.role !== "researcher" && args.role !== "reviewer") || typeof args.task !== "string" || !args.task.trim())
        throw new Error("Invalid delegation request");
      const cwd = this.directories.get(String(params.threadId));
      if (!cwd) throw new Error("Delegating conversation not found");
      worker = await this.utility(args.role, cwd);
      const turn = await this.start(worker, args.task);
      delegated = { threadId: worker, turnId: turn };
      parentKey = `${params.threadId}:${params.turnId}`;
      const children = this.delegations.get(parentKey) || new Set();
      children.add(delegated);
      this.delegations.set(parentKey, children);
      const done = await this.wait(worker, turn);
      const status = (done.turn as { status?: string; error?: { message?: string } }) || {};
      if (status.status !== "completed") throw new Error(status.error?.message || "Worker failed");
      const result = this.output(worker, turn);
      if (!result) throw new Error("Worker returned no answer");
      this.send({ id, result: { contentItems: [{ type: "inputText", text: result }], success: true } });
    } catch (error) {
      if (this.process?.stdin.writable)
        this.send({ id, result: { contentItems: [{ type: "inputText", text: error instanceof Error ? error.message : String(error) }], success: false } });
    } finally {
      if (parentKey && delegated) {
        const children = this.delegations.get(parentKey);
        children?.delete(delegated);
        if (!children?.size) this.delegations.delete(parentKey);
      }
      if (worker) await this.release(worker);
    }
  }
  create(cwd: string) { return this.thread("session", cwd, false, "danger-full-access"); }
  utility(role: "coordinator" | "researcher" | "reviewer", cwd: string, tools: ClientTool[] = []) {
    return this.thread(role, cwd, true, "read-only", tools);
  }
  async resume(threadId: string, cwd: string) {
    if (this.loaded.has(threadId)) return;
    await this.request("thread/resume", { threadId, cwd, developerInstructions: instructions("session") });
    this.directories.set(threadId, cwd);
    this.loaded.add(threadId);
  }
  async name(threadId: string, name: string) { await this.request("thread/name/set", { threadId, name }); }
  async start(threadId: string, text: string, options: { effort?: "low" | "high"; outputSchema?: Record<string, unknown> } = {}) {
    const result = await this.request("turn/start", { threadId, input: input(text), effort: options.effort || "high", ...(options.outputSchema && { outputSchema: options.outputSchema }) });
    const turn = result.turn as { id: string };
    if (!turn?.id) throw new Error("Codex did not return a turn ID");
    return turn.id;
  }
  async wait(threadId: string, turnId: string): Promise<Record<string, unknown>> {
    const key = `${threadId}:${turnId}`;
    const completed = this.completed.get(key);
    if (completed) { this.completed.delete(key); return completed; }
    return new Promise((resolve, reject) => this.waiters.set(key, { resolve, reject }));
  }
  output(threadId: string, turnId: string) {
    const key = `${threadId}:${turnId}`;
    const value = this.outputs.get(key);
    this.outputs.delete(key);
    return value;
  }
  async release(threadId: string) {
    this.utilityThreads.delete(threadId);
    this.loaded.delete(threadId);
    this.directories.delete(threadId);
    this.clientTools.delete(threadId);
    if (this.process?.stdin.writable) await this.request("thread/unsubscribe", { threadId }).catch(() => undefined);
  }
  steer(threadId: string, turnId: string, text: string) {
    return this.request("turn/steer", { threadId, expectedTurnId: turnId, input: input(text) });
  }
  interrupt(threadId: string, turnId: string) { return this.request("turn/interrupt", { threadId, turnId }); }
  async transcript(threadId: string) {
    const result = await this.request("thread/read", { threadId, includeTurns: true });
    const thread = result.thread as { turns?: Array<{ items?: Array<Record<string, unknown>> }> };
    return (thread.turns || []).flatMap((turn) => (turn.items || []).flatMap((item) => {
      if (item.type === "userMessage") {
        const content = item.content as Array<{ type: string; text?: string }>;
        const text = content?.filter((part) => part.type === "text").map((part) => part.text || "").join("\n").trim();
        return text ? [{ role: "user", text }] : [];
      }
      if (item.type === "agentMessage" && (item.phase === "final_answer" || item.phase === null)) {
        const text = String(item.text || "").trim();
        return text ? [{ role: "assistant", text }] : [];
      }
      return [];
    }));
  }
  async close() { this.process?.kill(); }
}
