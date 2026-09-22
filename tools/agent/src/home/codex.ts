import { HOME_SESSION_ID, type HomeEntry, type RuntimeConfig, type SessionCard, type TurnRequest } from "../conversation/types.js";
import type { Store } from "../conversation/store.js";
import { CodexAppServer, CodexDisconnectedError } from "../codex/app-server.js";
import { READ_CONVERSATION_TOOL } from "../codex/conversation-tools.js";
import { ephemeralToolTurn } from "../codex/ephemeral.js";
import { classifiedError } from "../codex/notifications.js";
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
  description: "Queue a follow-up as the next turn in an existing Agent task conversation.",
  inputSchema: {
    type: "object",
    properties: {
      sessionId: { type: "string" },
      title: { type: "string", description: "A short title for this Home entry." },
      text: { type: "string", description: "Follow-up work; omit to show the existing conversation in Home." },
    },
    required: ["sessionId", "title"],
    additionalProperties: false,
  },
};

const STEER_TASK = {
  name: "steer_task",
  description: "Add an immediate correction or instruction to a task that is currently working.",
  inputSchema: {
    type: "object",
    properties: {
      sessionId: { type: "string" },
      title: { type: "string", description: "A short title for this Home entry." },
      text: { type: "string", description: "A clear, self-contained instruction for the active turn." },
    },
    required: ["sessionId", "title", "text"],
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

  async compose(request: TurnRequest, conversations: SessionCard[], entries: HomeEntry[], signal?: AbortSignal): Promise<HomeAction[]> {
    const actions: HomeAction[] = [];
    const states = new Map(this.store.homeEntries().filter((entry) => entry.sessionId && entry.state)
      .map((entry) => [entry.sessionId!, entry.state]));
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
      `Recent Home activity: ${JSON.stringify([...entries].sort((a, b) => b.updatedAt.localeCompare(a.updatedAt)).slice(0, 12)
        .map(({ sessionId, title, body, state, summary }) => ({ sessionId, title, body, state, summary })))}`,
    ].filter(Boolean).join("\n");
    await this.retry(() => {
      actions.length = 0;
      return this.toolTurn(
        "You route requests; never do the work or answer it. Rewrite each work request into a clear, self-contained instruction and give new tasks a short specific title. Use start_task for new conversations. Use continue_task for a follow-up that should run as the next turn. Use steer_task only when the user explicitly asks to change, correct, or add to work that is currently running. Use find_conversations when the target is not listed, then read_conversation only when its preview is insufficient. Omit text only when the user wants to open a conversation without adding work. Preserve relevant context. Reuse a saved conversation's cwd for new work in that project; use the terminal directory for the current project. Personal tasks have no cwd. If uncertain, start one task with the full request. Output only tool calls.",
        prompt, [START_TASK, CONTINUE_TASK, STEER_TASK, FIND_CONVERSATIONS, READ_CONVERSATION_TOOL], (name, args) => {
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
            const title = String(args.title ?? "").trim().slice(0, 64);
            const sessionId = String(args.sessionId ?? "");
            if (!title || !this.store.getSession(sessionId) || sessionId === HOME_SESSION_ID) {
              return response(false, "Choose an existing conversation.");
            }
            actions.push({ type: "continue", sessionId, title, ...(text ? { text } : {}) });
            return response(true, "Conversation opened.");
          }
          if (name === STEER_TASK.name) {
            const text = String(args.text ?? "").trim();
            const title = String(args.title ?? "").trim().slice(0, 64);
            const sessionId = String(args.sessionId ?? "");
            if (!title || !text || !this.store.getSession(sessionId) || sessionId === HOME_SESSION_ID) {
              return response(false, "Choose an active conversation and provide an instruction.");
            }
            actions.push({ type: "steer", sessionId, title, text });
            return response(true, "Active work updated.");
          }
          return response(false, "Unknown tool.");
        }, signal);
    });
    if (!actions.length) throw new Error("Home could not route this request. Try again.");
    return actions;
  }

  async summarize(input: Parameters<HomeBackend["summarize"]>[0], signal?: AbortSignal): ReturnType<HomeBackend["summarize"]> {
    let report: { state: "ready" | "needs_input" | "failed"; summary: string } | null = null;
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
    if (!report) throw new Error("Home did not receive a task update.");
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
    await ephemeralToolTurn({
      client: this.client,
      cwd: this.config.homeDir,
      instructions,
      prompt,
      tools: dynamicTools,
      effort: "none",
      failureMessage: "The Home turn failed.",
      signal,
      onTool: (name, args) => ({ response: handle(name, args) }),
    });
  }
}
