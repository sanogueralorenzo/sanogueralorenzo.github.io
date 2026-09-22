import { on } from "node:events";
import { HOME_SESSION_ID, type RuntimeConfig, type SessionCard, type TaskReport, type TurnRequest } from "../conversation/types.js";
import type { Store } from "../conversation/store.js";
import { MODEL } from "../local/config.js";
import { CodexAppServer, CodexDisconnectedError } from "../codex/app-server.js";
import { READ_CONVERSATION_TOOL } from "../codex/conversation-tools.js";
import { classifiedError, nextForThread, object, type Notifications } from "../codex/notifications.js";
import { openFolder } from "../codex/workspace-tool.js";
import type { HomeAction, HomeBackend } from "./backend.js";

const START_TASK = {
  name: "start_task",
  description: "Start independent work in a new durable Agent task conversation.",
  inputSchema: {
    type: "object",
    properties: {
      text: { type: "string", description: "Work to start now; omit to create an idle conversation." },
      title: { type: "string", description: "A short, specific title." },
      cwd: { type: "string", description: "Absolute project folder, only when the task needs one." },
    },
    required: ["title"],
    additionalProperties: false,
  },
};

const CONTINUE_TASK = {
  name: "continue_task",
  description: "Send a follow-up to one existing Agent task conversation.",
  inputSchema: {
    type: "object",
    properties: { sessionId: { type: "string" }, text: { type: "string", description: "Follow-up work; omit to show the existing conversation in Home." } },
    required: ["sessionId"],
    additionalProperties: false,
  },
};

const FIND_CONVERSATIONS = {
  name: "find_conversations",
  description: "Find an older saved conversation by project, title, or message text before resuming it.",
  inputSchema: {
    type: "object",
    properties: { query: { type: "string" } },
    required: ["query"],
    additionalProperties: false,
  },
};

const REPORT_TASK = {
  name: "report_task",
  description: "Return one concise Home update about a task turn.",
  inputSchema: {
    type: "object",
    properties: {
      state: { type: "string", enum: ["ready", "needs_input", "failed"] },
      summary: { type: "string", description: "One line, at most 12 words, stating the outcome or needed action." },
    },
    required: ["state", "summary"],
    additionalProperties: false,
  },
};

function response(success: boolean, text: string) {
  return { success, contentItems: [{ type: "inputText", text }] };
}

export class CodexHomeBackend implements HomeBackend {
  constructor(
    private readonly config: RuntimeConfig,
    private readonly store: Store,
    private readonly client: CodexAppServer,
  ) {}

  async compose(request: TurnRequest, conversations: SessionCard[], reports: TaskReport[], signal?: AbortSignal): Promise<HomeAction[]> {
    const actions: HomeAction[] = [];
    const states = new Map(this.store.taskReports().map((report) => [report.sessionId, report.state]));
    const conversationState = (sessionId: string) => {
      const latestRun = this.store.latestRun(sessionId);
      if (latestRun?.state === "running") return "working";
      return states.get(sessionId) ?? "idle";
    };
    const prompt = [
      `User request: ${request.text}`,
      `Recent Home requests: ${JSON.stringify(this.store.getMessages(HOME_SESSION_ID, 8)
        .filter((message) => message.role === "user").slice(-4).map((message) => message.content.slice(0, 300)))}`,
      request.cwd ? `Terminal directory: ${request.cwd}` : "",
      `Recent conversations: ${JSON.stringify(conversations.slice(0, 12).map(({ id, cwd, title, preview }) => ({ id, cwd, title, preview })))}`,
      `Recent tasks: ${JSON.stringify([...reports].sort((a, b) => b.updatedAt.localeCompare(a.updatedAt)).slice(0, 12)
        .map(({ sessionId, title, state, summary }) => ({ sessionId, title, state, summary })))}`,
    ].filter(Boolean).join("\n");
    await this.retry(() => {
      actions.length = 0;
      return this.toolTurn(
        "You route requests; never do the work or answer it. Use start_task for new conversations and continue_task to resume or update an existing one, even if it is working. Use find_conversations when the target is not listed, then read_conversation only when a preview is insufficient to choose confidently. Include text only when the user asks for work; omit it when they only want a conversation opened in Home. Preserve relevant context in the work text. Reuse a saved conversation's cwd for new work in that project; use the terminal directory for the current project. Personal tasks have no cwd. If uncertain, start one task with the full request. Output only tool calls.",
        prompt, [START_TASK, CONTINUE_TASK, FIND_CONVERSATIONS, READ_CONVERSATION_TOOL], (name, args) => {
          if (name === FIND_CONVERSATIONS.name) {
            const query = String(args.query ?? "").trim();
            const found = query ? this.store.findConversations(query)
              .map((conversation) => ({ ...conversation, state: conversationState(conversation.id) })) : [];
            return response(Boolean(query), JSON.stringify(found));
          }
          if (name === READ_CONVERSATION_TOOL.name) {
            const sessionId = String(args.sessionId ?? "");
            const session = this.store.getSession(sessionId);
            if (!session || sessionId === HOME_SESSION_ID) return response(false, "Conversation not found.");
            const before = typeof args.before === "number" && Number.isSafeInteger(args.before) && args.before > 0
              ? args.before : undefined;
            return response(true, JSON.stringify({
              conversation: {
                id: session.id,
                title: session.title,
                cwd: session.cwd,
                updatedAt: session.updatedAt,
                state: conversationState(sessionId),
              },
              ...this.store.readConversation(sessionId, before, 6, 1_000),
            }));
          }
          if (name === START_TASK.name) {
            const text = String(args.text ?? "").trim();
            const title = String(args.title ?? "").trim().slice(0, 64);
            if (!title) return response(false, "A new conversation needs a title.");
            const cwd = args.cwd === undefined ? undefined : openFolder(args.cwd, this.config.homeDir).cwd;
            if (args.cwd !== undefined && !cwd) return response(false, "Choose a specific accessible project folder.");
            actions.push({ type: "start", title, ...(text ? { text } : {}), ...(cwd ? { cwd } : {}) });
            return response(true, "Conversation opened.");
          }
          if (name === CONTINUE_TASK.name) {
            const text = String(args.text ?? "").trim();
            const sessionId = String(args.sessionId ?? "");
            if (!this.store.getSession(sessionId) || sessionId === HOME_SESSION_ID) {
              return response(false, "Choose an existing conversation.");
            }
            actions.push({ type: "continue", sessionId, ...(text ? { text } : {}) });
            return response(true, "Conversation opened.");
          }
          return response(false, "Unknown tool.");
        }, signal);
    });
    if (!actions.length) throw new Error("Home could not route this request. Try again.");
    return actions;
  }

  async summarize(input: Parameters<HomeBackend["summarize"]>[0], signal?: AbortSignal): ReturnType<HomeBackend["summarize"]> {
    let report: Pick<TaskReport, "state" | "summary"> | null = null;
    await this.retry(() => {
      report = null;
      return this.toolTurn(
        "You report a task turn back to Agent Home. Call report_task exactly once. Use ready for a finished result, needs_input only if the user must answer a question, failed for an unsuccessful turn. Write a plain one-line outcome, at most 12 words. No preamble or praise.",
        `Task: ${input.title}\nRequest: ${input.request.slice(0, 1_000)}\nState: ${input.state}\nResult:\n${input.output.slice(-6_000)}`,
        [REPORT_TASK], (name, args) => {
          if (name !== REPORT_TASK.name) return response(false, "Unknown tool.");
          const state = args.state;
          const summary = String(args.summary ?? "").trim().replace(/\s+/g, " ").split(" ").slice(0, 12).join(" ");
          if (!summary || (state !== "ready" && state !== "needs_input" && state !== "failed")) return response(false, "State and summary are required.");
          report = { state: input.state === "complete" ? state : "failed", summary };
          return response(true, "Reported.");
        }, signal);
    });
    if (!report) throw new Error("Home did not receive a task report.");
    return report;
  }

  private async retry<T>(operation: () => Promise<T>): Promise<T> {
    try { return await operation(); }
    catch (error) {
      if (!(error instanceof CodexDisconnectedError)) throw classifiedError(error);
      await this.client.restart();
      return operation();
    }
  }

  private async toolTurn(
    instructions: string,
    prompt: string,
    dynamicTools: object[],
    handle: (name: string, args: Record<string, unknown>) => ReturnType<typeof response>,
    signal?: AbortSignal,
  ): Promise<void> {
    if (signal?.aborted) throw new DOMException("Interrupted", "AbortError");
    const started = await this.client.request<{ thread: { id: string } }>("thread/start", {
      model: MODEL,
      cwd: this.config.homeDir,
      approvalPolicy: "never",
      sandbox: "read-only",
      ephemeral: true,
      threadSource: "appServer",
      dynamicTools,
      developerInstructions: instructions,
    });
    const threadId = started.thread.id;
    const lifetime = new AbortController();
    const queue = on(this.client, "notification", { signal: lifetime.signal }) as Notifications;
    const abort = () => lifetime.abort();
    signal?.addEventListener("abort", abort, { once: true });
    if (signal?.aborted) abort();
    let turnId = "";
    let completed = false;
    try {
      const turn = await this.client.request<{ turn: { id: string } }>("turn/start", {
        threadId,
        input: [{ type: "text", text: prompt, text_elements: [] }],
        model: MODEL,
        effort: "none",
      });
      turnId = turn.turn.id;
      while (true) {
        const { id, method, params } = await nextForThread(queue, threadId);
        const eventTurnId = params.turnId ?? object(params.turn).id;
        if (eventTurnId && eventTurnId !== turnId) continue;
        if (method === "item/tool/call" && id !== undefined) {
          this.client.respond(id, handle(String(params.tool ?? ""), object(params.arguments)));
        } else if (method === "turn/completed") {
          completed = true;
          const result = object(params.turn);
          if (result.status === "completed") return;
          if (result.status === "interrupted") throw new DOMException("Interrupted", "AbortError");
          throw classifiedError(object(result.error).message ?? "The Home turn failed.");
        }
      }
    } finally {
      lifetime.abort();
      signal?.removeEventListener("abort", abort);
      if (turnId && !completed) await this.client.request("turn/interrupt", { threadId, turnId }).catch(() => undefined);
      await this.client.request("thread/unsubscribe", { threadId }).catch(() => undefined);
    }
  }
}
