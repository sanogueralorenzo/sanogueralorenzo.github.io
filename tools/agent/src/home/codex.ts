import { HOME_SESSION_ID, type HomeEntry, type RuntimeConfig, type SessionCard, type TurnRequest } from "../conversation/types.js";
import type { Store } from "../conversation/store.js";
import { CodexAppServer } from "../codex/app-server.js";
import { READ_CONVERSATION_TOOL } from "../codex/conversation-tools.js";
import { ephemeralToolTurn } from "../codex/ephemeral.js";
import { retryDisconnected } from "../codex/notifications.js";
import { openFolder } from "../codex/workspace-tool.js";
import type { HomeAction, HomeBackend } from "./backend.js";

const ROUTE_TASKS = {
  name: "route_tasks",
  description: "Submit the complete routing plan for this Home message in one call.",
  inputSchema: {
    type: "object",
    properties: {
      routes: {
        type: "array",
        minItems: 1,
        items: {
          type: "object",
          properties: {
            type: { type: "string", enum: ["start", "continue", "steer"] },
            source: { type: "string", description: "An exact quote from the user message identifying this distinct request. Quotes must not overlap." },
            title: { type: "string", description: "A short, specific title for this Home entry." },
            text: { type: "string", description: "Optional coordinator brief to accompany the user's original message verbatim. Add useful context or scope; never replace or paraphrase the original. Omit only when opening an idle conversation." },
            sessionId: { type: "string", description: "Existing conversation ID for continue or steer." },
            entryId: { type: "string", description: "Existing Home entry ID only when continuing that same task." },
            cwd: { type: "string", description: "Absolute project folder for a new task, only when needed." },
          },
          required: ["type", "source", "title"],
          additionalProperties: false,
        },
      },
    },
    required: ["routes"],
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
      summary: { type: "string", description: "A short conversational update with enough detail to communicate the answer, outcome, or needed action." },
    },
    required: ["state", "summary"],
    additionalProperties: false,
  },
};

function response(success: boolean, text: string) {
  return { success, contentItems: [{ type: "inputText", text }] };
}

const ROUTER_INSTRUCTIONS = `Route the user's message into the fewest actions that cover its distinct outcomes and destinations. Keep dependent steps together; split independent outcomes even when they share context. Do not perform the work.

Call route_tasks once with the complete plan. For each action, quote a unique, non-overlapping part of the message and give a short title. Keep the user's original message verbatim when it is dispatched; use text only as a separate coordinator brief with useful context or scope. Never replace or paraphrase the original. When splitting independent work, make each brief identify its assigned part and do not duplicate work assigned to another session. Choose start for new work, continue to queue a follow-up in an existing conversation, or steer to change its active work now only when the user explicitly asks. Set entryId when continuing the same Home task; a shared conversation alone does not make work the same task.

Use find_conversations when a destination is not listed and read_conversation only when its preview lacks needed context. Carry necessary context between actions. Reuse a saved project's directory or the terminal directory for current project work; omit it for personal work. Omit the instruction only when opening an idle conversation. Output only tool calls.`;

const REPORTER_INSTRUCTIONS = "Report the turn in one report_task call. Use ready for a completed result, needs_input when the user must respond, and failed for an unsuccessful turn. Write a brief conversational update, usually a few sentences, with enough detail to communicate the answer, concrete outcome, or next action. For a conversational reply, use the reply itself. Output only the tool call.";

export class CodexHomeBackend implements HomeBackend {
  constructor(
    private readonly config: RuntimeConfig,
    private readonly store: Store,
    private readonly client: CodexAppServer,
  ) {}

  async compose(request: TurnRequest, conversations: SessionCard[], entries: HomeEntry[], signal?: AbortSignal): Promise<HomeAction[]> {
    let actions: HomeAction[] | null = null;
    const states = new Map(this.store.home.entries().filter((entry) => entry.sessionId && entry.state)
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
      `Recent conversations: ${JSON.stringify(conversations.slice(0, 12).map(({ id, cwd, title, preview }) => ({ id, cwd, title, preview, state: conversationState(id) })))}`,
      `Recent Home activity: ${JSON.stringify([...entries].sort((a, b) => b.updatedAt.localeCompare(a.updatedAt)).slice(0, 12)
        .map(({ id, sessionId, body, requests, state, summary }) => ({ id, sessionId, body,
          requests: requests.slice(-2).map(({ text }) => text.slice(0, 160)), state, summary })))}`,
    ].filter(Boolean).join("\n");
    await retryDisconnected(this.client, () => {
      actions = null;
      return this.toolTurn(
        ROUTER_INSTRUCTIONS,
        prompt, [ROUTE_TASKS, FIND_CONVERSATIONS, READ_CONVERSATION_TOOL], (name, args) => {
          if (actions) return response(false, "This Home message is already routed.");
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
          if (name === ROUTE_TASKS.name) {
            const result = this.parseRoutes(args.routes, request.text);
            if ("error" in result) return response(false, result.error);
            actions = result.actions;
            return response(true, `Routed ${actions.length} task${actions.length === 1 ? "" : "s"}.`);
          }
          return response(false, "Unknown tool.");
        }, signal, "low");
    });
    if (!actions) throw new Error("Home could not route this request. Try again.");
    return actions;
  }

  private parseRoutes(value: unknown, request: string): { actions: HomeAction[] } | { error: string } {
    if (!Array.isArray(value) || value.length === 0) return { error: "Include at least one route." };
    const actions: HomeAction[] = [];
    const spans: { start: number; end: number }[] = [];
    const sessions = new Set<string>();
    for (const item of value) {
      if (!item || typeof item !== "object" || Array.isArray(item)) return { error: "Each route must be an object." };
      const route = item as Record<string, unknown>;
      const source = typeof route.source === "string" ? route.source.trim() : "";
      const title = typeof route.title === "string" ? route.title.trim().slice(0, 64) : "";
      const text = typeof route.text === "string" ? route.text.trim() : "";
      if (!source || !title || (route.text !== undefined && typeof route.text !== "string")) {
        return { error: "Each route needs an exact source quote and a short title." };
      }
      let start = request.indexOf(source);
      while (start >= 0 && spans.some((span) => start < span.end && start + source.length > span.start)) {
        start = request.indexOf(source, start + 1);
      }
      if (start < 0) return { error: "Route source quotes must be exact, distinct, non-overlapping parts of the user message." };
      spans.push({ start, end: start + source.length });
      if (route.type === "start") {
        if (route.sessionId !== undefined || route.entryId !== undefined) return { error: "A new task cannot target an existing conversation or Home entry." };
        const cwd = route.cwd === undefined ? undefined : openFolder(route.cwd, this.config.homeDir).cwd;
        if (route.cwd !== undefined && !cwd) return { error: "Choose a specific accessible project folder." };
        actions.push({ type: "start", source, title, ...(text ? { text } : {}), ...(cwd ? { cwd } : {}) });
        continue;
      }
      if (route.type !== "continue" && route.type !== "steer") return { error: "Choose start, continue, or steer for each route." };
      const sessionId = typeof route.sessionId === "string" ? route.sessionId : "";
      if (!sessionId || sessionId === HOME_SESSION_ID || !this.store.getSession(sessionId) || route.cwd !== undefined) {
        return { error: "Choose a saved conversation for each continue or steer route." };
      }
      if (sessions.has(sessionId)) return { error: "Use one route per existing conversation; combine its requested work." };
      sessions.add(sessionId);
      const entryId = typeof route.entryId === "string" ? route.entryId : undefined;
      if (route.entryId !== undefined && (!entryId || this.store.home.entry(entryId)?.sessionId !== sessionId)) {
        return { error: "Choose a Home entry for this conversation or omit entryId for a new task." };
      }
      if (route.type === "steer") {
        if (!text) return { error: "A steering route needs an instruction." };
        actions.push({ type: "steer", source, title, sessionId, text, ...(entryId ? { entryId } : {}) });
      } else {
        actions.push({ type: "continue", source, title, sessionId, ...(text ? { text } : {}), ...(entryId ? { entryId } : {}) });
      }
    }
    return { actions };
  }

  async summarize(input: Parameters<HomeBackend["summarize"]>[0], signal?: AbortSignal): ReturnType<HomeBackend["summarize"]> {
    let report: { state: "ready" | "needs_input" | "failed"; summary: string } | null = null;
    await retryDisconnected(this.client, () => {
      report = null;
      return this.toolTurn(
        REPORTER_INSTRUCTIONS,
        `Task: ${input.title}\nRequest: ${input.request.slice(0, 1_000)}\nState: ${input.state}\nResult:\n${input.output.slice(-6_000)}`,
        [REPORT_TASK], (name, args) => {
          if (name !== REPORT_TASK.name) return response(false, "Unknown tool.");
          const state = args.state;
          const summary = String(args.summary ?? "").trim();
          if (!summary || (state !== "ready" && state !== "needs_input" && state !== "failed")) return response(false, "State and summary are required.");
          report = { state: input.state === "complete" ? state : "failed", summary };
          return response(true, "Reported.");
        }, signal, "low");
    });
    if (!report) throw new Error("Home did not receive a task update.");
    return report;
  }

  private async toolTurn(
    instructions: string,
    prompt: string,
    dynamicTools: object[],
    handle: (name: string, args: Record<string, unknown>) => ReturnType<typeof response>,
    signal?: AbortSignal,
    effort: "none" | "low" = "none",
  ): Promise<void> {
    await ephemeralToolTurn({
      client: this.client,
      homeDir: this.config.homeDir,
      cwd: this.config.homeDir,
      instructions,
      prompt,
      tools: dynamicTools,
      effort,
      failureMessage: "The Home turn failed.",
      signal,
      onTool: (name, args) => ({ response: handle(name, args) }),
    });
  }
}
