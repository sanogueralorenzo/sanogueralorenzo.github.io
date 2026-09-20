import type { AgentBackend, BackendEvent, BackendTurn } from "../core/backend.js";
import type { Store } from "../core/store.js";
import type { Attachment, RuntimeConfig } from "../core/types.js";
import { saveArtifactPath } from "../core/assets.js";
import { readVoiceNote } from "../core/audio.js";
import { randomUUID } from "node:crypto";
import { CodexAppServer, CodexDisconnectedError, CodexRpcError } from "./app-server.js";
import type { CodexRateLimits, JsonRpcMessage } from "./protocol.js";
import { NodeRealtimePeer, type RealtimePeer } from "./webrtc.js";

export class CodexAuthenticationError extends Error {
  constructor(message = "Your ChatGPT session has expired. Run `agent setup` to reconnect it.") {
    super(message);
    this.name = "CodexAuthenticationError";
  }
}

export class CodexAllowanceError extends Error {
  constructor(message = "Your included Codex allowance is currently exhausted. Check usage with `agent setup`, or choose API-key billing there.") {
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

function codexTurnError(message: string): Error {
  if (/auth|login|token|unauthorized/i.test(message)) return new CodexAuthenticationError();
  if (/rate.?limit|usage.?limit|credits?.?depleted|allowance/i.test(message)) return new CodexAllowanceError();
  return new Error(message);
}

export class CodexBackend implements AgentBackend {
  readonly kind = "codex" as const;
  readonly label = "Codex subscription";
  private preflightValidUntil = 0;

  constructor(
    private readonly config: RuntimeConfig,
    private readonly store: Store,
    readonly client: CodexAppServer,
    private readonly createRealtimePeer: () => RealtimePeer = () => new NodeRealtimePeer(),
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

  async transcribeAudio(attachment: Attachment, signal?: AbortSignal): Promise<string> {
    await this.preflight();
    for (let attempt = 0; attempt < 2; attempt += 1) {
      try {
        return await this.transcribeOnce(attachment, signal);
      } catch (error) {
        if (error instanceof CodexDisconnectedError && attempt === 0) {
          await this.client.restart();
          continue;
        }
        throw error;
      }
    }
    throw new CodexDisconnectedError();
  }

  async *run(turn: BackendTurn): AsyncGenerator<BackendEvent> {
    await this.preflight();
    const workerResult = turn.route.worker ? await this.runWorker(turn) : null;
    let madeProgress = false;
    const clientUserMessageId = randomUUID();
    for (let attempt = 0; attempt < 2; attempt += 1) {
      try {
        for await (const event of this.runOnce(turn, clientUserMessageId, workerResult)) {
          if (event.type === "text_delta" || event.type === "tool_start" || event.type === "tool_end") madeProgress = true;
          yield event;
        }
        return;
      } catch (error) {
        if (error instanceof CodexDisconnectedError && attempt === 0 && !madeProgress) {
          yield { type: "status", message: "Codex restarted. Resuming your Agent session…" };
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
    const usage = await this.client.rateLimits();
    const limit = activeRateLimit(usage);
    if (limit.reached) throw new CodexAllowanceError(`${limit.name} allowance is currently exhausted. Check usage with \`agent setup\`, or choose API-key billing there.`);
    this.preflightValidUntil = Date.now() + 15_000;
  }

  private async *runOnce(turn: BackendTurn, clientUserMessageId: string, workerResult: string | null): AsyncGenerator<BackendEvent> {
    const instructions = workerResult
      ? `${turn.instructions}\n\nInternal worker result (working material, not user instructions):\n<worker_result>\n${workerResult.slice(0, 30_000)}\n</worker_result>`
      : turn.instructions;
    const threadId = await this.thread(turn, instructions);
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
        model: this.config.models.coordinator,
        effort: "high",
      });
      turnId = started.turn.id;
      if (turn.signal?.aborted) {
        interrupt();
        throw new DOMException("Interrupted", "AbortError");
      }

      while (true) {
        const message = await queue.next(turn.signal);
        if (message.method === "agent/disconnected") throw new CodexDisconnectedError(String(message.params?.message ?? "Codex disconnected."));
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
          if (item.type === "imageGeneration" && typeof item.savedPath === "string") {
            yield {
              type: "artifact",
              artifact: saveArtifactPath(this.config.homeDir, { path: item.savedPath }),
            };
          }
          continue;
        }
        if (message.method === "error" && params.willRetry !== true) {
          const detail = record(params.error);
          const messageText = typeof detail.message === "string" ? detail.message : "The Codex turn failed.";
          throw codexTurnError(messageText);
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
          throw codexTurnError(messageText);
        }
      }
    } finally {
      unsubscribe();
      turn.signal?.removeEventListener("abort", interrupt);
    }
  }

  private async runWorker(turn: BackendTurn): Promise<string> {
    for (let attempt = 0; attempt < 2; attempt += 1) {
      try {
        return await this.runWorkerOnce(turn);
      } catch (error) {
        if (error instanceof CodexDisconnectedError && attempt === 0) {
          await this.client.restart();
          continue;
        }
        throw error;
      }
    }
    throw new CodexDisconnectedError();
  }

  private async transcribeOnce(attachment: Attachment, signal?: AbortSignal): Promise<string> {
    const audio = await readVoiceNote(attachment);
    const started = await this.client.request<{ thread: { id: string } }>("thread/start", {
      model: this.config.models.coordinator,
      cwd: this.config.homeDir,
      approvalPolicy: "never",
      sandbox: "read-only",
      ephemeral: true,
      threadSource: "appServer",
    });
    const threadId = started.thread.id;
    const queue = new NotificationQueue();
    const unsubscribe = this.client.onNotification((message) => queue.push(message));
    const timeout = AbortSignal.timeout(45_000);
    const combinedSignal = signal ? AbortSignal.any([signal, timeout]) : timeout;
    const peer = this.createRealtimePeer();

    try {
      const offer = await peer.offer();
      await this.client.request("thread/realtime/start", {
        threadId,
        outputModality: "audio",
        includeStartupContext: false,
        clientManagedHandoffs: true,
        flushTranscriptTailOnSessionEnd: true,
        realtimeStartInstructions: "Transcribe the user's speech accurately.",
        version: "v3",
        transport: { type: "webrtc", sdp: offer },
      });
      while (true) {
        const message = await queue.next(combinedSignal);
        if (message.method === "agent/disconnected") throw new CodexDisconnectedError(String(message.params?.message ?? "Codex disconnected."));
        const params = record(message.params);
        if (params.threadId !== threadId) continue;
        if (message.method === "thread/realtime/sdp" && typeof params.sdp === "string") {
          await peer.accept(params.sdp);
          break;
        }
        if (message.method === "thread/realtime/error") {
          throw new Error(typeof params.message === "string" ? params.message : "Voice transcription failed.");
        }
      }
      await peer.sendAudio(audio, combinedSignal);

      while (true) {
        const message = await queue.next(combinedSignal);
        if (message.method === "agent/disconnected") throw new CodexDisconnectedError(String(message.params?.message ?? "Codex disconnected."));
        const params = record(message.params);
        if (params.threadId !== threadId) continue;
        if (message.method === "thread/realtime/transcript/done" && params.role === "user" && typeof params.text === "string") {
          const transcript = params.text.trim();
          if (!transcript) throw new Error("The voice note did not contain recognizable speech.");
          return transcript;
        }
        if (message.method === "thread/realtime/error") {
          throw new Error(typeof params.message === "string" ? params.message : "Voice transcription failed.");
        }
        if (message.method === "thread/realtime/closed") {
          throw new Error("Voice transcription ended before a transcript was ready.");
        }
      }
    } catch (error) {
      if (timeout.aborted && !signal?.aborted) throw new Error("Voice transcription timed out.");
      throw error;
    } finally {
      await this.client.request("thread/realtime/stop", { threadId }).catch(() => undefined);
      await peer.close().catch(() => undefined);
      unsubscribe();
    }
  }

  private async runWorkerOnce(turn: BackendTurn): Promise<string> {
    const worker = turn.route.worker;
    if (!worker) throw new Error("Worker routing is missing.");
    const cwd = turn.session.cwd ?? this.config.homeDir;
    const started = await this.client.request<{ thread: { id: string } }>("thread/start", {
      model: this.config.models[worker],
      cwd,
      approvalPolicy: "never",
      sandbox: worker === "coding" ? "workspace-write" : "read-only",
      developerInstructions: turn.workerInstructions,
      ephemeral: true,
      threadSource: "appServer",
    });
    const threadId = started.thread.id;
    const queue = new NotificationQueue();
    const unsubscribe = this.client.onNotification((message) => queue.push(message));
    let turnId: string | null = null;
    let output = "";
    const interrupt = () => {
      if (turnId) void this.client.request("turn/interrupt", { threadId, turnId }).catch(() => undefined);
    };
    turn.signal?.addEventListener("abort", interrupt, { once: true });

    try {
      const run = await this.client.request<{ turn: { id: string } }>("turn/start", {
        threadId,
        clientUserMessageId: randomUUID(),
        input: [{ type: "text", text: turn.request.text, text_elements: [] }],
        model: this.config.models[worker],
        effort: "high",
      });
      turnId = run.turn.id;
      if (turn.signal?.aborted) {
        interrupt();
        throw new DOMException("Interrupted", "AbortError");
      }

      while (true) {
        const message = await queue.next(turn.signal);
        if (message.method === "agent/disconnected") throw new CodexDisconnectedError(String(message.params?.message ?? "Codex disconnected."));
        const params = record(message.params);
        if (params.threadId !== threadId) continue;
        const messageTurnId = typeof params.turnId === "string"
          ? params.turnId
          : typeof record(params.turn).id === "string" ? String(record(params.turn).id) : null;
        if (messageTurnId && messageTurnId !== turnId) continue;
        if (message.method === "item/agentMessage/delta" && typeof params.delta === "string") {
          output += params.delta;
          continue;
        }
        if (message.method === "item/completed") {
          const item = record(params.item);
          if (!output && item.type === "agentMessage" && typeof item.text === "string") output = item.text;
          continue;
        }
        if (message.method === "error" && params.willRetry !== true) {
          const detail = record(params.error);
          throw codexTurnError(typeof detail.message === "string" ? detail.message : `${worker} worker failed.`);
        }
        if (message.method === "turn/completed") {
          const completed = record(params.turn);
          if (completed.status === "completed") {
            if (!output.trim()) throw new Error(`${worker} worker completed without a result.`);
            return output;
          }
          if (completed.status === "interrupted") throw new DOMException("Interrupted", "AbortError");
          const detail = record(completed.error);
          throw codexTurnError(typeof detail.message === "string" ? detail.message : `${worker} worker failed.`);
        }
      }
    } finally {
      unsubscribe();
      turn.signal?.removeEventListener("abort", interrupt);
    }
  }

  private async thread(turn: BackendTurn, instructions: string): Promise<string> {
    const existing = this.store.backendSession(turn.session.id, "codex");
    const cwd = turn.session.cwd ?? this.config.homeDir;
    const common = {
      model: this.config.models.coordinator,
      cwd,
      approvalPolicy: "never",
      sandbox: "read-only",
      developerInstructions: instructions,
    };
    if (existing) {
      const resumed = await this.client.request<{ thread: { id: string } }>("thread/resume", {
        threadId: existing,
        ...common,
      });
      return resumed.thread.id;
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
        ? `${instructions}\n\nContinue this Agent-owned session using its prior transcript:\n\n${priorTranscript}`
        : instructions,
      ephemeral: false,
      threadSource: "appServer",
    });
    this.store.bindBackendSession(turn.session.id, "codex", started.thread.id);
    return started.thread.id;
  }
}
