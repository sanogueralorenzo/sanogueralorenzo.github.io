import { randomUUID } from "node:crypto";
import { on } from "node:events";
import { saveArtifactPath } from "../workspace/assets.js";
import type { AgentBackend, BackendEvent, BackendTurn } from "../conversation/backend.js";
import { MODEL } from "../local/config.js";
import type { Store } from "../conversation/store.js";
import type { Attachment, RuntimeConfig } from "../conversation/types.js";
import { CodexAppServer, CodexDisconnectedError } from "./app-server.js";
import { CONVERSATION_TOOLS, conversationTool } from "./conversation-tools.js";
import { classifiedError, nextForThread, object, type Notifications } from "./notifications.js";
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
  constructor(
    private readonly config: RuntimeConfig,
    private readonly store: Store,
    readonly client: CodexAppServer,
    private readonly createRealtimePeer: () => RealtimePeer = () => new NodeRealtimePeer(),
  ) {}

  async transcribeAudio(attachment: Attachment, signal?: AbortSignal): Promise<string> {
    return this.retry(() => transcribeVoice(this.client, this.config.homeDir, attachment, this.createRealtimePeer, signal));
  }

  async discardSession(sessionId: string): Promise<void> {
    const threadId = this.store.codexThread(sessionId);
    if (threadId) await this.client.request("thread/delete", { threadId });
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

  private async retry<T>(operation: () => Promise<T>): Promise<T> {
    try {
      return await operation();
    } catch (error) {
      if (!(error instanceof CodexDisconnectedError)) throw classifiedError(error);
      await this.client.restart();
      return operation();
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
    let navigation = "";
    let openedFolder = "";
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
        model: MODEL,
        effort: "high",
      });
      turnId = started.turn.id;
      if (turn.signal?.aborted) {
        interrupt();
        throw new DOMException("Interrupted", "AbortError");
      }
      while (true) {
        const { id, method, params } = await nextForThread(queue, threadId);
        const eventTurnId = params.turnId ?? object(params.turn).id;
        if (eventTurnId && eventTurnId !== turnId) continue;
        if (method === "item/tool/call" && id !== undefined) {
          if (params.tool === OPEN_FOLDER_TOOL.name) {
            const answer = openFolder(object(params.arguments).path, this.config.homeDir);
            if (answer.cwd) openedFolder = answer.cwd;
            this.client.respond(id, answer.result);
          } else {
            const answer = conversationTool(this.store, turn.sessionTools ?? [], String(params.tool ?? ""), object(params.arguments));
            if (answer.navigateTo) navigation = answer.navigateTo;
            this.client.respond(id, answer.result);
          }
        } else if (method === "item/agentMessage/delta" && typeof params.delta === "string") {
          if (!navigation && !openedFolder) {
            sawText = true;
            yield { type: "text_delta", delta: params.delta };
          }
        } else if (method === "item/started") {
          const item = object(params.item);
          const name = toolName(item);
          if (name && typeof item.id === "string") yield { type: "tool_start", name, callId: item.id };
        } else if (method === "item/completed") {
          const item = object(params.item);
          if (!navigation && !openedFolder && !sawText && item.type === "agentMessage" && typeof item.text === "string") {
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
            if (navigation) yield { type: "navigate", sessionId: navigation };
            else if (openedFolder) yield { type: "workspace", cwd: openedFolder };
            yield { type: "done" };
            return;
          }
          if (completed.status === "interrupted") throw new DOMException("Interrupted", "AbortError");
          throw classifiedError(object(completed.error).message ?? "The Codex turn failed.");
        }
      }
    } finally {
      lifetime.abort();
      turn.signal?.removeEventListener("abort", interrupt);
    }
  }

  private async sessionThread(turn: BackendTurn): Promise<string> {
    const existing = this.store.codexThread(turn.session.id);
    const common = {
      model: MODEL,
      cwd: turn.session.cwd ?? this.config.homeDir,
      approvalPolicy: "never",
      sandbox: turn.session.cwd ? "workspace-write" : "read-only",
      developerInstructions: turn.instructions,
      dynamicTools: [OPEN_FOLDER_TOOL, ...(turn.sessionTools ? CONVERSATION_TOOLS : [])],
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
