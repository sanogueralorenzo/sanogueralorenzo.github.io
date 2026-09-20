import type { AgentBackend, BackendEvent, BackendTurn } from "../core/backend.js";
import type { Store } from "../core/store.js";
import type { RuntimeConfig } from "../core/types.js";
import { randomUUID } from "node:crypto";
import { CodexAppServer, CodexDisconnectedError, CodexRpcError } from "./app-server.js";
import type { CodexRateLimits, JsonRpcMessage } from "./protocol.js";

export class CodexAuthenticationError extends Error {
  constructor(message = "Your ChatGPT session has expired. Run `a1r setup` to reconnect it.") {
    super(message);
    this.name = "CodexAuthenticationError";
  }
}

export class CodexAllowanceError extends Error {
  constructor(message = "Your included Codex allowance is currently exhausted. Check usage with `a1r setup`, or choose API-key billing there.") {
    super(message);
    this.name = "CodexAllowanceError";
  }
}

class NotificationQueue {
  private items: JsonRpcMessage[] = [];
  private waiters: Array<(message: JsonRpcMessage) => void> = [];

  push(message: JsonRpcMessage): void {
    const waiter = this.waiters.shift();
    if (waiter) waiter(message);
    else this.items.push(message);
  }

  async next(signal?: AbortSignal): Promise<JsonRpcMessage> {
    const item = this.items.shift();
    if (item) return item;
    if (signal?.aborted) throw new DOMException("Interrupted", "AbortError");
    return new Promise((resolve, reject) => {
      const onAbort = () => {
        const index = this.waiters.indexOf(onMessage);
        if (index >= 0) this.waiters.splice(index, 1);
        reject(new DOMException("Interrupted", "AbortError"));
      };
      const onMessage = (message: JsonRpcMessage) => {
        signal?.removeEventListener("abort", onAbort);
        resolve(message);
      };
      this.waiters.push(onMessage);
      signal?.addEventListener("abort", onAbort, { once: true });
    });
  }
}

function activeRateLimit(limits: CodexRateLimits): { reached: boolean; name: string } {
  const snapshots = limits.rateLimitsByLimitId
    ? Object.values(limits.rateLimitsByLimitId)
    : [limits.rateLimits];
  const reached = limits.ordinaryUsageAllowed === false
    || snapshots.some((snapshot) => Boolean(snapshot?.rateLimitReachedType));
  const name = snapshots.find((snapshot) => snapshot?.limitName)?.limitName ?? "Codex";
  return { reached, name };
}

function itemName(item: Record<string, unknown>): string | null {
  switch (item.type) {
    case "commandExecution": return "command";
    case "fileChange": return "file_change";
    case "mcpToolCall": return typeof item.tool === "string" ? item.tool : "mcp_tool";
    case "dynamicToolCall": return typeof item.tool === "string" ? item.tool : "tool";
    case "collabAgentToolCall": return "delegate";
    case "webSearch": return "web_search";
    case "imageGeneration": return "image_generation";
    default: return null;
  }
}

function itemSummary(item: Record<string, unknown>): string {
  if (item.type === "commandExecution") {
    const status = typeof item.status === "string" ? item.status : "complete";
    const exit = typeof item.exitCode === "number" ? ` (exit ${item.exitCode})` : "";
    return `${status}${exit}`;
  }
  if (typeof item.status === "string") return item.status;
  if (typeof item.success === "boolean") return item.success ? "complete" : "failed";
  return "complete";
}

function record(value: unknown): Record<string, unknown> {
  return value && typeof value === "object" ? value as Record<string, unknown> : {};
}

export class CodexBackend implements AgentBackend {
  readonly kind = "codex" as const;
  readonly label = "Codex subscription";
  private preflightValidUntil = 0;

  constructor(
    private readonly config: RuntimeConfig,
    private readonly store: Store,
    readonly client: CodexAppServer,
  ) {}

  async isConfigured(): Promise<boolean> {
    if (!this.client.isInstalled()) return false;
    try {
      const status = await this.client.account(false);
      return status.account?.type === "chatgpt";
    } catch {
      return false;
    }
  }

  async *run(turn: BackendTurn): AsyncGenerator<BackendEvent> {
    await this.preflight();
    let madeProgress = false;
    const clientUserMessageId = randomUUID();
    for (let attempt = 0; attempt < 2; attempt += 1) {
      try {
        for await (const event of this.runOnce(turn, clientUserMessageId)) {
          if (event.type === "text_delta" || event.type === "tool_start" || event.type === "tool_end") madeProgress = true;
          yield event;
        }
        return;
      } catch (error) {
        if (error instanceof CodexDisconnectedError && attempt === 0 && !madeProgress) {
          yield { type: "status", message: "Codex restarted. Resuming your A1R session…" };
          await this.client.restart();
          continue;
        }
        if (error instanceof CodexRpcError && /auth|login|token|unauthorized/i.test(error.message)) {
          throw new CodexAuthenticationError();
        }
        if (error instanceof CodexRpcError && /rate.?limit|usage.?limit|credits?.?depleted|allowance/i.test(error.message)) {
          throw new CodexAllowanceError();
        }
        throw error;
      }
    }
  }

  async close(): Promise<void> {
    await this.client.stop();
  }

  private async preflight(): Promise<void> {
    if (Date.now() < this.preflightValidUntil) return;
    const account = await this.client.account(false).catch((error) => {
      if (error instanceof CodexRpcError && /auth|login|token|unauthorized/i.test(error.message)) {
        throw new CodexAuthenticationError();
      }
      throw error;
    });
    if (account.account?.type !== "chatgpt") throw new CodexAuthenticationError();
    try {
      const usage = await this.client.rateLimits();
      const limit = activeRateLimit(usage);
      if (limit.reached) throw new CodexAllowanceError(`${limit.name} allowance is currently exhausted. Check usage with \`a1r setup\`, or choose API-key billing there.`);
    } catch (error) {
      // Older documented app-server versions may not provide rate-limit data.
      if (error instanceof CodexAllowanceError) throw error;
      if (!(error instanceof CodexRpcError && error.code === -32601)) throw error;
    }
    this.preflightValidUntil = Date.now() + 15_000;
  }

  private async *runOnce(turn: BackendTurn, clientUserMessageId: string): AsyncGenerator<BackendEvent> {
    const threadId = await this.thread(turn);
    const queue = new NotificationQueue();
    const unsubscribe = this.client.onNotification((message) => queue.push(message));
    let turnId: string | null = null;
    let sawDelta = false;
    const interrupt = () => {
      if (turnId) void this.client.request("turn/interrupt", { threadId, turnId }).catch(() => undefined);
    };
    turn.signal?.addEventListener("abort", interrupt, { once: true });

    try {
      const started = await this.client.request<{ turn: { id: string } }>("turn/start", {
        threadId,
        clientUserMessageId,
        input: [{ type: "text", text: turn.request.text, text_elements: [] }],
      });
      turnId = started.turn.id;
      if (turn.signal?.aborted) {
        interrupt();
        throw new DOMException("Interrupted", "AbortError");
      }

      while (true) {
        const message = await queue.next(turn.signal);
        if (message.method === "a1r/disconnected") throw new CodexDisconnectedError(String(message.params?.message ?? "Codex disconnected."));
        const params = record(message.params);
        if (params.threadId !== threadId) continue;
        const messageTurnId = typeof params.turnId === "string"
          ? params.turnId
          : typeof record(params.turn).id === "string" ? String(record(params.turn).id) : null;
        if (messageTurnId && messageTurnId !== turnId) continue;

        if (message.method === "item/agentMessage/delta" && typeof params.delta === "string") {
          sawDelta = true;
          yield { type: "text_delta", delta: params.delta };
          continue;
        }
        if (message.method === "item/started") {
          const item = record(params.item);
          const name = itemName(item);
          if (name && typeof item.id === "string") yield { type: "tool_start", name, callId: item.id };
          continue;
        }
        if (message.method === "item/completed") {
          const item = record(params.item);
          if (!sawDelta && item.type === "agentMessage" && typeof item.text === "string" && item.text) {
            sawDelta = true;
            yield { type: "text_delta", delta: item.text };
          }
          const name = itemName(item);
          if (name && typeof item.id === "string") {
            yield { type: "tool_end", name, callId: item.id, summary: itemSummary(item) };
          }
          continue;
        }
        if (message.method === "error" && params.willRetry !== true) {
          const detail = record(params.error);
          const messageText = typeof detail.message === "string" ? detail.message : "The Codex turn failed.";
          if (/auth|login|token|unauthorized/i.test(messageText)) throw new CodexAuthenticationError();
          if (/rate.?limit|usage.?limit|credits?.?depleted|allowance/i.test(messageText)) throw new CodexAllowanceError();
          throw new Error(messageText);
        }
        if (message.method === "turn/completed") {
          const completed = record(params.turn);
          const status = completed.status;
          if (status === "completed") {
            yield { type: "done", responseId: turnId };
            return;
          }
          if (status === "interrupted") throw new DOMException("Interrupted", "AbortError");
          const turnError = record(completed.error);
          const messageText = typeof turnError.message === "string" ? turnError.message : "The Codex turn failed.";
          if (/auth|login|token|unauthorized/i.test(messageText)) throw new CodexAuthenticationError();
          if (/rate.?limit|usage.?limit|credits?.?depleted|allowance/i.test(messageText)) throw new CodexAllowanceError();
          throw new Error(messageText);
        }
      }
    } finally {
      unsubscribe();
      turn.signal?.removeEventListener("abort", interrupt);
    }
  }

  private async thread(turn: BackendTurn): Promise<string> {
    const existing = this.store.backendSession(turn.session.id, "codex");
    const cwd = turn.session.cwd ?? this.config.homeDir;
    const common = {
      cwd,
      approvalPolicy: "never",
      sandbox: turn.route.kind === "coding" ? "workspace-write" : "read-only",
      developerInstructions: turn.instructions,
    };
    if (existing) {
      try {
        const resumed = await this.client.request<{ thread: { id: string } }>("thread/resume", {
          threadId: existing,
          ...common,
        });
        return resumed.thread.id;
      } catch (error) {
        if (!(error instanceof CodexRpcError && /not found|unknown thread|does not exist/i.test(error.message))) throw error;
        this.store.removeBackendSession(turn.session.id, "codex");
      }
    }
    const priorTranscript = this.store.getMessages(turn.session.id, this.config.maxHistoryMessages)
      .slice(0, -1)
      .filter((message) => message.role !== "tool")
      .map((message) => `${message.role}: ${message.content}`)
      .join("\n\n")
      .slice(-20_000);
    const started = await this.client.request<{ thread: { id: string } }>("thread/start", {
      ...common,
      developerInstructions: priorTranscript
        ? `${turn.instructions}\n\nContinue this A1R-owned session using its prior transcript:\n\n${priorTranscript}`
        : turn.instructions,
      ephemeral: false,
      threadSource: "appServer",
    });
    this.store.bindBackendSession(turn.session.id, "codex", started.thread.id);
    return started.thread.id;
  }
}
