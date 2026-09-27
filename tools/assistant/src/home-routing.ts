import { homedir } from "node:os";
import type { CodexService } from "./codex.ts";
import type { HomeEntry, HomeMessage, State } from "./state.ts";

export type Route = { mode: "start"; title: string; cwd?: string } | { mode: "continue"; sessionId: string };
const routeSchema = { type: "object", properties: {
  mode: { type: "string", enum: ["start", "continue"] }, title: { type: "string" },
  sessionId: { type: "string" }, cwd: { type: "string" },
}, required: ["mode", "title", "sessionId", "cwd"], additionalProperties: false };

function parseRoute(value: unknown, state: State): Route {
  if (!value || typeof value !== "object") throw new Error("Coordinator did not choose a destination");
  const route = value as Record<string, unknown>;
  if (route.mode === "start") {
    if (route.sessionId) throw new Error("New work cannot use a saved session ID");
    if (typeof route.title !== "string" || !route.title.trim()) throw new Error("New work needs a title");
    if (typeof route.cwd !== "string") throw new Error("Project directory must be a string");
    return { mode: "start", title: route.title, cwd: route.cwd || undefined };
  }
  if (route.mode === "continue") {
    if (typeof route.sessionId !== "string" || !state.data.sessions.some((session) => session.id === route.sessionId))
      throw new Error("Continue with an exact saved session ID from the preview or search result");
    return { mode: "continue", sessionId: route.sessionId };
  }
  throw new Error("Home supports only start or continue");
}

export class HomeRouter {
  private readonly state: State;
  private readonly codex: CodexService;
  private readonly cwd: string;
  constructor(state: State, codex: CodexService, cwd: string) {
    this.state = state;
    this.codex = codex;
    this.cwd = cwd;
  }

  async discover(message: HomeMessage): Promise<Route> {
    const entries = this.state.data.entries;
    const requests = (entry: HomeEntry) => this.state.data.messages
      .filter((item) => item.entryId === entry.id).map((item) => item.text);
    const sessions = this.state.data.sessions.map((session) => {
      const related = entries.filter((entry) => entry.sessionId === session.id)
        .sort((a, b) => b.updatedAt.localeCompare(a.updatedAt));
      return { id: session.id, title: session.title, status: session.status, cwd: session.cwd,
        updatedAt: related[0]?.updatedAt || session.createdAt,
        recent: related.slice(0, 2).map((entry) => ({ request: (requests(entry).at(-1) || "").slice(0, 200), lastUpdate: entry.updates.at(-1)?.text.slice(0, 200) })) };
    }).sort((a, b) => b.updatedAt.localeCompare(a.updatedAt));
    const words = [...new Set(message.text.toLowerCase().match(/[\p{L}\p{N}._/-]+/gu) || [])].filter((word) => word.length > 2);
    const matches = sessions.map((session) => {
      const related = entries.filter((entry) => entry.sessionId === session.id);
      const haystack = [session.title, session.cwd, ...related.flatMap((entry) => [...requests(entry), entry.updates.at(-1)?.text || ""])].join(" ").toLowerCase();
      return { session, score: words.filter((word) => haystack.includes(word)).length };
    }).filter(({ score }) => score > 0).sort((a, b) => b.score - a.score || b.session.updatedAt.localeCompare(a.session.updatedAt))
      .slice(0, 8).map(({ session }) => session);
    const candidates = [...new Map([...sessions.slice(0, 12), ...matches].map((session) => [session.id, session])).values()];
    const threadId = await this.codex.utility("coordinator", this.cwd, [{
      name: "find_conversations",
      description: "Find older saved conversations by project, title, or message text when the destination is missing from the recent preview.",
      inputSchema: { type: "object", properties: { query: { type: "string" } }, required: ["query"], additionalProperties: false },
      execute: async ({ query }) => {
        if (typeof query !== "string") return "Search query must be text";
        const words = [...new Set(query.toLowerCase().match(/[\p{L}\p{N}._/-]+/gu) || [])].filter((word) => word.length > 2 &&
          !["the", "and", "for", "with", "about", "that", "this", "what", "whether", "resume", "continue"].includes(word));
        const found = words.length ? sessions.map((session) => {
          const related = entries.filter((entry) => entry.sessionId === session.id);
          const haystack = [session.title, session.cwd, ...related.flatMap((entry) => [...requests(entry), entry.updates.at(-1)?.text || ""])]
            .join(" ").toLowerCase();
          const score = words.filter((word) => haystack.includes(word)).length + (haystack.includes(query.toLowerCase()) ? words.length : 0);
          return { session, score };
        }).filter(({ score }) => score >= Math.min(2, words.length)).sort((a, b) => b.score - a.score ||
          b.session.updatedAt.localeCompare(a.session.updatedAt)).slice(0, 8).map(({ session }) => session) : [];
        return JSON.stringify(found);
      },
    }, {
      name: "read_conversation",
      description: "Read recent messages of one saved conversation by its listed ID when its preview is ambiguous.",
      inputSchema: { type: "object", properties: { sessionId: { type: "string" } }, required: ["sessionId"], additionalProperties: false },
      execute: async ({ sessionId }) => {
        if (typeof sessionId !== "string" || !this.state.data.sessions.some((session) => session.id === sessionId)) return "Conversation not found";
        return JSON.stringify((await this.codex.transcript(sessionId)).slice(-12)).slice(0, 12000);
      },
    }]);
    try {
      let prompt = `Original user message (verbatim):\n${message.text}\n\nCurrent workspace: ${this.cwd}\nPersonal work directory: ${homedir()}\nRecent and matching saved conversations: ${JSON.stringify(candidates)}\n\nChoose one destination. Use find_conversations for an older destination missing from the preview and read_conversation only when a preview is ambiguous. Use empty strings for unused fields.`;
      for (let attempt = 0; attempt < 3; attempt++) {
        const turnId = await this.codex.start(threadId, prompt, { effort: "low", outputSchema: routeSchema });
        const completed = await this.codex.wait(threadId, turnId);
        const turn = completed.turn as { status: string; error?: { message?: string } };
        if (turn.status !== "completed") throw new Error(turn.error?.message || "Coordinator failed");
        const text = this.codex.output(threadId, turnId);
        try { return parseRoute(JSON.parse(text || ""), this.state); }
        catch (error) {
          if (attempt === 2) throw error;
          prompt = `Invalid destination: ${error instanceof Error ? error.message : String(error)}. Correct the choice and return one valid JSON destination.`;
        }
      }
      throw new Error("Coordinator did not choose a destination");
    } finally { await this.codex.release(threadId); }
  }
}
