import { Type } from "typebox";
import type { PiService } from "./pi.ts";
import type { HomeMessage, State, TaskRole } from "./state.ts";

export type Route = { mode: "start" | "continue" | "steer"; agent: TaskRole; title: string; source: string; task: string;
  sessionId?: string; entryId?: string; newEntry?: boolean; cwd?: string };

function namedTaskMatches(source: string, state: State) {
  const name = source.match(/\b(?:in|for|on|continue|resume)\s+(?:the|my|this|that)\s+(.{2,80}?)\s+(?:task|conversation|session)\b/i)?.[1]?.toLowerCase();
  if (!name) return [];
  return state.data.sessions.filter((session) => {
    const descriptions = [session.title, ...state.data.entries.filter((entry) => entry.sessionId === session.id)
      .flatMap((entry) => [entry.scope, entry.sourceText])];
    return descriptions.some((description) => description.toLowerCase().includes(name));
  });
}

export function parseRoutes(raw: string, message: HomeMessage, state: State): Route[] {
  const plan = JSON.parse(raw.trim().replace(/^```(?:json)?\s*/i, "").replace(/\s*```$/, "")) as { routes?: Route[] };
  if (!Array.isArray(plan?.routes) || !plan.routes.length || plan.routes.length > 8) throw new Error("Coordinator returned an invalid plan");
  const sources = new Set<string>();
  const sessions = new Set<string>();
  for (const route of plan.routes) {
    if (!route || typeof route !== "object" || !["start", "continue", "steer"].includes(route.mode) ||
      !["personal", "code", "scout", "reviewer"].includes(route.agent) ||
      typeof route.title !== "string" || !route.title.trim() || typeof route.source !== "string" || !route.source.trim() ||
      typeof route.task !== "string" || !route.task.trim()) throw new Error("Coordinator returned an incomplete route");
    if (!message.text.includes(route.source) || sources.has(route.source)) throw new Error("Each route must quote a distinct part of the message");
    sources.add(route.source);
    const namedMatches = namedTaskMatches(plan.routes.length === 1 ? message.text : route.source, state);
    if (route.mode === "start") {
      if (route.sessionId || route.entryId) throw new Error("A new task cannot use an existing conversation or Home entry");
      delete route.newEntry;
      if (/^\s*(?:resume|take me back to|return to|pick up)\b/i.test(route.source))
        throw new Error("An explicit resume request must target a saved conversation; use find_conversations");
      if (namedMatches.length) throw new Error(`This quote names a saved task. Continue its conversation: ${namedMatches.map((item) => item.id).join(", ")}`);
      continue;
    }
    if (!route.sessionId) throw new Error("Coordinator omitted a conversation ID");
    const existing = state.data.sessions.find((session) => session.id === route.sessionId);
    if (!existing) throw new Error("Coordinator selected an unknown conversation");
    if (namedMatches.length === 1 && namedMatches[0].id !== existing.id) throw new Error(`This quote names saved conversation ${namedMatches[0].id}`);
    if (route.agent !== (existing.role || "personal")) throw new Error("Coordinator changed a conversation's agent role");
    delete route.cwd;
    if (route.mode === "steer" && !/\b(steer|interrupt|change|instead|stop|redirect|focus)\b/i.test(message.text))
      throw new Error("Steering requires an explicit request");
    if (sessions.has(route.sessionId)) throw new Error("Coordinator assigned two outcomes to one conversation");
    sessions.add(route.sessionId);
    if (/\bseparately\b/i.test(route.source) && route.entryId) throw new Error("Separate work needs newEntry: true, not an existing entryId");
    if (route.newEntry && (route.entryId || route.mode === "steer")) throw new Error("Separate Home work cannot reuse or steer an entry");
    if (route.entryId && !state.data.entries.some((entry) => entry.id === route.entryId && entry.sessionId === route.sessionId))
      throw new Error("Coordinator selected an unrelated Home entry");
    if (!route.entryId && !route.newEntry) {
      const entries = state.data.entries.filter((entry) => entry.sessionId === route.sessionId);
      if (entries.length === 1 && (route.mode === "steer" || /\b(?:the|my|this|that)\s+.{2,80}?\s+task\b/i.test(route.source)))
        route.entryId = entries[0].id;
      else throw new Error("A continuation needs entryId for a follow-up, or newEntry: true for separate work in that conversation");
    }
  }
  return plan.routes;
}

export class HomeRouter {
  private readonly state: State;
  private readonly pi: PiService;
  private readonly cwd: string;
  constructor(state: State, pi: PiService, cwd: string) {
    this.state = state;
    this.pi = pi;
    this.cwd = cwd;
  }

  async discover(message: HomeMessage) {
    const entries = this.state.data.entries;
    const sessions = this.state.data.sessions.map((session) => {
      const related = entries.filter((entry) => entry.sessionId === session.id)
        .sort((a, b) => b.updatedAt.localeCompare(a.updatedAt));
      return { id: session.id, title: session.title, agent: session.role || "personal", status: session.status, cwd: session.cwd,
        updatedAt: related[0]?.updatedAt || session.createdAt,
        recent: related.slice(0, 2).map((entry) => ({ id: entry.id, scope: entry.scope, status: entry.status,
          lastUpdate: entry.updates.at(-1)?.text.slice(0, 200) })) };
    }).sort((a, b) => b.updatedAt.localeCompare(a.updatedAt));
    const findConversations = {
      name: "find_conversations", label: "Find saved conversations",
      description: "Find older saved conversations by project, title, or message text. Read-only; use when the destination is missing from the recent preview.",
      parameters: Type.Object({ query: Type.String() }),
      execute: async (_callId: string, params: { query: string }) => {
        const query = params.query.trim().toLowerCase();
        const words = [...new Set(query.match(/[\p{L}\p{N}._/-]+/gu) || [])].filter((word) => word.length > 2 &&
          !["the", "and", "for", "with", "about", "that", "this", "what", "whether", "resume", "continue"].includes(word));
        const matches = query && words.length ? sessions.map((session) => {
          const related = entries.filter((entry) => entry.sessionId === session.id);
          const haystack = [session.title, session.cwd, ...related.flatMap((entry) => [entry.scope, entry.sourceText, entry.updates.at(-1)?.text || ""])]
            .join(" ").toLowerCase();
          const score = words.filter((word) => haystack.includes(word)).length + (haystack.includes(query) ? words.length : 0);
          return { session, score };
        }).filter(({ score }) => score >= Math.min(2, words.length)).sort((a, b) => b.score - a.score ||
          b.session.updatedAt.localeCompare(a.session.updatedAt)).slice(0, 8).map(({ session }) => session) : [];
        return { content: [{ type: "text" as const, text: JSON.stringify(matches) }], details: undefined };
      },
    };
    const readConversation = {
      name: "read_conversation", label: "Read saved conversation",
      description: "Read recent messages of one saved conversation by its listed ID when its preview is insufficient for routing.",
      parameters: Type.Object({ sessionId: Type.String() }),
      execute: async (_callId: string, params: { sessionId: string }) => {
        const record = this.state.data.sessions.find((item) => item.id === params.sessionId);
        return { content: [{ type: "text" as const, text: record ? JSON.stringify(this.pi.transcript(record.file).slice(-12)).slice(0, 12000) : "Conversation not found" }], details: undefined };
      },
    };
    let accepted: Route[] | undefined;
    const routeTasks = {
      name: "route_tasks", label: "Submit Home routing plan",
      description: "Submit the complete routing plan for this Home message. Invalid plans return a reason so you can correct them.",
      parameters: Type.Object({ routes: Type.Array(Type.Object({
        mode: Type.Union([Type.Literal("start"), Type.Literal("continue"), Type.Literal("steer")]),
        agent: Type.Union([Type.Literal("personal"), Type.Literal("code"), Type.Literal("scout"), Type.Literal("reviewer")]),
        title: Type.String(), source: Type.String(), task: Type.String(),
        sessionId: Type.Optional(Type.String()), entryId: Type.Optional(Type.String()), newEntry: Type.Optional(Type.Boolean()), cwd: Type.Optional(Type.String()),
      }), { minItems: 1, maxItems: 8 }) }),
      execute: async (_callId: string, params: { routes: Route[] }) => {
        if (accepted) return { content: [{ type: "text" as const, text: "This Home message already has an accepted plan." }], details: undefined };
        try {
          accepted = parseRoutes(JSON.stringify(params), message, this.state);
          return { content: [{ type: "text" as const, text: `Accepted ${accepted.length} route${accepted.length === 1 ? "" : "s"}.` }], details: undefined };
        } catch (error) {
          const reason = error instanceof Error ? error.message : String(error);
          return { content: [{ type: "text" as const, text: `Invalid plan: ${reason}. Correct it and call route_tasks again.` }], details: undefined };
        }
      },
    };
    await this.pi.utility("coordinator", `Original user message (verbatim):\n${message.text}\n\nCurrent workspace: ${this.cwd}\nRecent conversations and Home entries: ${JSON.stringify(sessions.slice(0, 12).map(({ updatedAt, ...session }) => session))}\n\nCall route_tasks with one complete plan.`,
      this.cwd, [findConversations, readConversation, routeTasks], () => accepted ? JSON.stringify({ routes: accepted }) : undefined);
    if (!accepted) throw new Error("Coordinator did not submit a routing plan");
    return JSON.stringify({ routes: accepted });
  }
}
