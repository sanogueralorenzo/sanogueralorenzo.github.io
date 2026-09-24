import { Type } from "typebox";
import type { PiService } from "./pi.ts";
import type { HomeEntry, HomeMessage, State, TaskRole } from "./state.ts";

export type Route = { mode: "start"; agent: TaskRole; title: string; cwd?: string } | { mode: "continue"; sessionId: string };

function parseRoute(value: unknown, state: State): Route {
  if (!value || typeof value !== "object") throw new Error("Submit one Home destination");
  const route = value as Record<string, unknown>;
  if (route.mode === "start") {
    if (route.sessionId) throw new Error("New work cannot use a saved session ID");
    if (!["personal", "code", "scout", "reviewer"].includes(String(route.agent)) ||
      typeof route.title !== "string" || !route.title.trim()) throw new Error("New work needs a role and title");
    if (route.cwd !== undefined && typeof route.cwd !== "string") throw new Error("Project directory must be a string");
    return { mode: "start", agent: route.agent as TaskRole, title: route.title, cwd: route.cwd as string | undefined };
  }
  if (route.mode === "continue") {
    if (typeof route.sessionId !== "string" || !state.data.sessions.some((session) => session.id === route.sessionId))
      throw new Error("Continue with an exact saved session ID from the preview or search result");
    return { mode: "continue", sessionId: route.sessionId };
  }
  throw new Error("Home supports only start or continue. Steering is an explicit action inside an open session");
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

  async discover(message: HomeMessage): Promise<Route> {
    const entries = this.state.data.entries;
    const requests = (entry: HomeEntry) => this.state.data.messages
      .filter((item) => item.entryId === entry.id).map((item) => item.text);
    const sessions = this.state.data.sessions.map((session) => {
      const related = entries.filter((entry) => entry.sessionId === session.id)
        .sort((a, b) => b.updatedAt.localeCompare(a.updatedAt));
      return { id: session.id, title: session.title, agent: session.role || "personal", status: session.status, cwd: session.cwd,
        updatedAt: related[0]?.updatedAt || session.createdAt,
        recent: related.slice(0, 2).map((entry) => ({ request: (requests(entry).at(-1) || "").slice(0, 200), lastUpdate: entry.updates.at(-1)?.text.slice(0, 200) })) };
    }).sort((a, b) => b.updatedAt.localeCompare(a.updatedAt));
    const findConversations = {
      name: "find_conversations", label: "Find saved conversations",
      description: "Find older saved conversations by project, title, or message text when the destination is missing from the recent preview.",
      parameters: Type.Object({ query: Type.String() }),
      execute: async (_callId: string, params: { query: string }) => {
        const query = params.query.trim().toLowerCase();
        const words = [...new Set(query.match(/[\p{L}\p{N}._/-]+/gu) || [])].filter((word) => word.length > 2 &&
          !["the", "and", "for", "with", "about", "that", "this", "what", "whether", "resume", "continue"].includes(word));
        const matches = query && words.length ? sessions.map((session) => {
          const related = entries.filter((entry) => entry.sessionId === session.id);
          const haystack = [session.title, session.cwd, ...related.flatMap((entry) => [...requests(entry), entry.updates.at(-1)?.text || ""])]
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
      description: "Read recent messages of one saved conversation by its listed ID when its preview is ambiguous.",
      parameters: Type.Object({ sessionId: Type.String() }),
      execute: async (_callId: string, params: { sessionId: string }) => {
        const record = this.state.data.sessions.find((item) => item.id === params.sessionId);
        return { content: [{ type: "text" as const, text: record ? JSON.stringify(this.pi.transcript(record.file).slice(-12)).slice(0, 12000) : "Conversation not found" }], details: undefined };
      },
    };
    let accepted: Route | undefined;
    const routeHome = {
      name: "route_home", label: "Choose Home destination",
      description: "Choose one start or continue destination for the entire Home message. Invalid choices return a reason to correct.",
      parameters: Type.Object({
        mode: Type.Union([Type.Literal("start"), Type.Literal("continue")]),
        agent: Type.Optional(Type.Union([Type.Literal("personal"), Type.Literal("code"), Type.Literal("scout"), Type.Literal("reviewer")])),
        title: Type.Optional(Type.String()), sessionId: Type.Optional(Type.String()), cwd: Type.Optional(Type.String()),
      }),
      execute: async (_callId: string, params: unknown) => {
        if (accepted) return { content: [{ type: "text" as const, text: "Destination already accepted." }], details: undefined };
        try {
          accepted = parseRoute(params, this.state);
          return { content: [{ type: "text" as const, text: "Destination accepted." }], details: undefined };
        } catch (error) {
          const reason = error instanceof Error ? error.message : String(error);
          return { content: [{ type: "text" as const, text: `Invalid destination: ${reason}. Correct it and call route_home again.` }], details: undefined };
        }
      },
    };
    await this.pi.utility("coordinator", `Original user message (verbatim):\n${message.text}\n\nCurrent workspace: ${this.cwd}\nRecent saved conversations: ${JSON.stringify(sessions.slice(0, 12).map(({ updatedAt, ...session }) => session))}\n\nCall route_home once for the entire message.`,
      this.cwd, [findConversations, readConversation, routeHome], () => accepted ? JSON.stringify(accepted) : undefined);
    if (!accepted) throw new Error("Coordinator did not choose a destination");
    return accepted;
  }
}
