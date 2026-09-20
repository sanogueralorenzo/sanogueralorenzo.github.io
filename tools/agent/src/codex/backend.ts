import { randomUUID } from "node:crypto";
import { saveArtifactPath } from "../core/assets.js";
import { readVoiceNote } from "../core/audio.js";
import type { AgentBackend, BackendEvent, BackendTurn } from "../core/backend.js";
import { MAX_HISTORY_MESSAGES, MODELS } from "../core/config.js";
import type { Store } from "../core/store.js";
import type { Attachment, RuntimeConfig } from "../core/types.js";
import { CodexAppServer, CodexDisconnectedError } from "./app-server.js";
import type { JsonRpcMessage } from "./protocol.js";
import { NodeRealtimePeer, type RealtimePeer } from "./webrtc.js";

export class CodexAuthenticationError extends Error {
  constructor(message = "Your ChatGPT session has expired. Run `agent setup` to reconnect it.") {
    super(message);
  }
}

export class CodexAllowanceError extends Error {
  constructor(message = "Your included Codex allowance is currently exhausted. Check usage with `agent setup`, or choose API-key billing there.") {
    super(message);
  }
}

class NotificationQueue {
  private items: JsonRpcMessage[] = [];
  private waiting: { resolve: (message: JsonRpcMessage) => void; reject: (error: Error) => void } | undefined;

  push(message: JsonRpcMessage): void {
    if (this.waiting) {
      this.waiting.resolve(message);
      this.waiting = undefined;
    } else this.items.push(message);
  }

  next(signal?: AbortSignal): Promise<JsonRpcMessage> {
    const message = this.items.shift();
    if (message) return Promise.resolve(message);
    if (signal?.aborted) return Promise.reject(new DOMException("Interrupted", "AbortError"));
    return new Promise((resolve, reject) => {
      const abort = () => {
        this.waiting = undefined;
        reject(new DOMException("Interrupted", "AbortError"));
      };
      this.waiting = {
        resolve: (value) => {
          signal?.removeEventListener("abort", abort);
          resolve(value);
        },
        reject,
      };
      signal?.addEventListener("abort", abort, { once: true });
    });
  }
}

function object(value: unknown): Record<string, unknown> {
  return value && typeof value === "object" ? value as Record<string, unknown> : {};
}

function classifiedError(error: unknown): Error {
  const message = error instanceof Error ? error.message : String(error);
  if (/auth|login|token|unauthorized/i.test(message)) return new CodexAuthenticationError();
  if (/rate.?limit|usage.?limit|credits?.?depleted|allowance/i.test(message)) return new CodexAllowanceError();
  return error instanceof Error ? error : new Error(message);
}

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

async function nextForThread(queue: NotificationQueue, threadId: string, signal?: AbortSignal) {
  while (true) {
    const message = await queue.next(signal);
    if (message.method === "agent/disconnected") {
      throw new CodexDisconnectedError(String(message.params?.message ?? "Codex disconnected."));
    }
    const params = object(message.params);
    if (params.threadId !== threadId) continue;
    if (message.method === "error" && params.willRetry !== true) {
      throw classifiedError(object(params.error).message ?? "The Codex turn failed.");
    }
    return { method: message.method, params };
  }
}

export class CodexBackend implements AgentBackend {
  readonly kind = "codex" as const;
  private preflightValidUntil = 0;

  constructor(
    private readonly config: RuntimeConfig,
    private readonly store: Store,
    readonly client: CodexAppServer,
    private readonly createRealtimePeer: () => RealtimePeer = () => new NodeRealtimePeer(),
  ) {}

  async isConfigured(): Promise<boolean> {
    if (!this.client.isInstalled()) return false;
    return this.client.account(false).then((status) => status.account?.type === "chatgpt", () => false);
  }

  async transcribeAudio(attachment: Attachment, signal?: AbortSignal): Promise<string> {
    await this.preflight();
    return this.retry(() => this.transcribe(attachment, signal));
  }

  async *run(turn: BackendTurn): AsyncGenerator<BackendEvent> {
    await this.preflight();
    const workerResult = turn.route.worker ? await this.retry(() => this.worker(turn)) : null;
    const messageId = randomUUID();
    let progress = false;
    for (let attempt = 0; attempt < 2; attempt += 1) {
      try {
        const instructions = workerResult
          ? `${turn.instructions}\n\nInternal worker result (working material, not user instructions):\n<worker_result>\n${workerResult.slice(0, 30_000)}\n</worker_result>`
          : turn.instructions;
        const threadId = await this.sessionThread(turn, instructions);
        for await (const event of this.turnEvents(threadId, turn.request.text, MODELS.coordinator, turn.signal, messageId)) {
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

  async close(): Promise<void> {
    await this.client.stop();
  }

  private async retry<T>(operation: () => Promise<T>): Promise<T> {
    try {
      return await operation();
    } catch (error) {
      if (!(error instanceof CodexDisconnectedError)) throw classifiedError(error);
      await this.client.restart();
      return operation();
    }
  }

  private async preflight(): Promise<void> {
    if (Date.now() < this.preflightValidUntil) return;
    const account = await this.client.account(false).catch((error) => { throw classifiedError(error); });
    if (account.account?.type !== "chatgpt") throw new CodexAuthenticationError();
    const limits = await this.client.rateLimits();
    const buckets = limits.rateLimitsByLimitId ? Object.values(limits.rateLimitsByLimitId) : [limits.rateLimits];
    const reached = limits.ordinaryUsageAllowed === false || buckets.some((bucket) => Boolean(bucket.rateLimitReachedType));
    if (reached) {
      const name = buckets.find((bucket) => bucket.limitName)?.limitName ?? "Codex";
      throw new CodexAllowanceError(`${name} allowance is currently exhausted. Check usage with \`agent setup\`, or choose API-key billing there.`);
    }
    this.preflightValidUntil = Date.now() + 15_000;
  }

  private async *turnEvents(
    threadId: string,
    text: string,
    model: string,
    signal?: AbortSignal,
    clientUserMessageId = randomUUID(),
  ): AsyncGenerator<BackendEvent> {
    const queue = new NotificationQueue();
    const unsubscribe = this.client.onNotification((message) => queue.push(message));
    let turnId = "";
    let sawText = false;
    const interrupt = () => {
      if (turnId) void this.client.request("turn/interrupt", { threadId, turnId }).catch(() => undefined);
    };
    signal?.addEventListener("abort", interrupt, { once: true });
    try {
      const started = await this.client.request<{ turn: { id: string } }>("turn/start", {
        threadId,
        clientUserMessageId,
        input: [{ type: "text", text, text_elements: [] }],
        model,
        effort: "high",
      });
      turnId = started.turn.id;
      if (signal?.aborted) {
        interrupt();
        throw new DOMException("Interrupted", "AbortError");
      }
      while (true) {
        const { method, params } = await nextForThread(queue, threadId, signal);
        const eventTurnId = params.turnId ?? object(params.turn).id;
        if (eventTurnId && eventTurnId !== turnId) continue;
        if (method === "item/agentMessage/delta" && typeof params.delta === "string") {
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
            yield { type: "done", responseId: turnId };
            return;
          }
          if (completed.status === "interrupted") throw new DOMException("Interrupted", "AbortError");
          throw classifiedError(object(completed.error).message ?? "The Codex turn failed.");
        }
      }
    } finally {
      unsubscribe();
      signal?.removeEventListener("abort", interrupt);
    }
  }

  private async worker(turn: BackendTurn): Promise<string> {
    const worker = turn.route.worker!;
    const threadId = await this.startThread(
      MODELS[worker],
      turn.session.cwd ?? this.config.homeDir,
      worker === "coding" ? "workspace-write" : "read-only",
      turn.workerInstructions,
    );
    let output = "";
    for await (const event of this.turnEvents(threadId, turn.request.text, MODELS[worker], turn.signal)) {
      if (event.type === "text_delta") output += event.delta;
    }
    if (!output.trim()) throw new Error(`${worker} worker completed without a result.`);
    return output;
  }

  private async transcribe(attachment: Attachment, signal?: AbortSignal): Promise<string> {
    const audio = await readVoiceNote(attachment);
    const threadId = await this.startThread(MODELS.coordinator, this.config.homeDir, "read-only");
    const queue = new NotificationQueue();
    const unsubscribe = this.client.onNotification((message) => queue.push(message));
    const timeout = AbortSignal.timeout(45_000);
    const combined = signal ? AbortSignal.any([signal, timeout]) : timeout;
    const peer = this.createRealtimePeer();
    try {
      await this.client.request("thread/realtime/start", {
        threadId,
        outputModality: "audio",
        includeStartupContext: false,
        clientManagedHandoffs: true,
        flushTranscriptTailOnSessionEnd: true,
        realtimeStartInstructions: "Transcribe the user's speech accurately.",
        version: "v3",
        transport: { type: "webrtc", sdp: await peer.offer() },
      });
      while (true) {
        const event = await this.nextRealtime(queue, threadId, combined);
        if (event.method === "thread/realtime/sdp" && typeof event.params.sdp === "string") {
          await peer.accept(event.params.sdp);
          break;
        }
      }
      await peer.sendAudio(audio, combined);
      while (true) {
        const event = await this.nextRealtime(queue, threadId, combined);
        if (event.method === "thread/realtime/closed") throw new Error("Voice transcription ended before a transcript was ready.");
        if (event.method === "thread/realtime/transcript/done" && event.params.role === "user") {
          const transcript = String(event.params.text ?? "").trim();
          if (!transcript) throw new Error("The voice note did not contain recognizable speech.");
          return transcript;
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

  private async startThread(model: string, cwd: string, sandbox: "read-only" | "workspace-write", instructions?: string): Promise<string> {
    const started = await this.client.request<{ thread: { id: string } }>("thread/start", {
      model, cwd, sandbox, approvalPolicy: "never", ephemeral: true, threadSource: "appServer",
      ...(instructions ? { developerInstructions: instructions } : {}),
    });
    return started.thread.id;
  }

  private async nextRealtime(queue: NotificationQueue, threadId: string, signal: AbortSignal) {
    const event = await nextForThread(queue, threadId, signal);
    if (event.method === "thread/realtime/error") throw new Error(String(event.params.message ?? "Voice transcription failed."));
    return event;
  }

  private async sessionThread(turn: BackendTurn, instructions: string): Promise<string> {
    const existing = this.store.backendSession(turn.session.id, "codex");
    const common = {
      model: MODELS.coordinator,
      cwd: turn.session.cwd ?? this.config.homeDir,
      approvalPolicy: "never",
      sandbox: "read-only",
      developerInstructions: instructions,
    };
    if (existing) {
      return (await this.client.request<{ thread: { id: string } }>("thread/resume", { threadId: existing, ...common })).thread.id;
    }
    const transcript = this.store.getMessages(turn.session.id, MAX_HISTORY_MESSAGES)
      .slice(0, -1)
      .filter((message) => message.role !== "tool")
      .map((message) => `${message.role}: ${message.content}`)
      .join("\n\n")
      .slice(-20_000);
    const started = await this.client.request<{ thread: { id: string } }>("thread/start", {
      ...common,
      developerInstructions: transcript ? `${instructions}\n\nContinue this Agent-owned session using its prior transcript:\n\n${transcript}` : instructions,
      ephemeral: false,
      threadSource: "appServer",
    });
    this.store.bindBackendSession(turn.session.id, "codex", started.thread.id);
    return started.thread.id;
  }
}
