import type { Data, HomeEntry, HomeMessage, Turn } from "../src/state.ts";
import type { Conversation } from "./api.ts";

export type Target = { id: string; text: string; role: "You" | "Agent"; sessionId?: string | null };
export type Row = Target & {
  title?: string;
  detail?: string;
  quote?: Target;
  replyable?: boolean;
};
export type Feed = {
  data: Data;
  conversation?: Conversation;
  progress: Map<string, string>;
  view: string;
};

function replyTarget(feed: Feed, id?: string): Target | undefined {
  if (!id) return;
  const message = feed.data.messages.find(item => item.id === id);
  if (message) return {
    id, text: message.text, role: "You",
    sessionId: feed.data.entries.find(entry => entry.id === message.entryId)?.sessionId,
  };
  for (const entry of feed.data.entries) {
    const update = entry.updates.find(item => item.id === id);
    if (update) return { id, text: update.text, role: "Agent", sessionId: entry.sessionId };
  }
}

function sessionTurns(feed: Feed) {
  return feed.data.turns.filter(turn => turn.sessionId === feed.view);
}

function dependencies(data: Data, turn?: Turn) {
  return turn?.dependsOn?.map(id => data.messages.find(message => message.id === id)?.text || "earlier task").join(", ");
}

function homeStatus(message: HomeMessage, entry: HomeEntry | undefined, turn?: Turn) {
  if (message.replacedBy) return "cancelled";
  if (turn) return turn.status === "running" ? "working" : "queued";
  if (entry?.status === "interrupted" && (entry.interruptedSourceId || entry.sourceId) === message.id) return "interrupted";
  const update = entry?.updates.filter(item => (item.sourceId || entry.sourceId) === message.id).at(-1);
  if (update) return { result: "ready", error: "failed", progress: "working" }[update.kind];
  return message.status === "routed" ? "queued" : message.status;
}

function homeRows(feed: Feed): Row[] {
  const { data, progress } = feed;
  const edited = new Set(data.messages.map(message => message.editOfId));
  const entries = new Map(data.entries.map(entry => [entry.id, entry]));
  const sources = new Map(data.messages.map(message => [message.id, message]));
  const turns = new Map(data.turns.map(turn => [turn.sourceId, turn]));
  const rows: (Row & { createdAt: string })[] = [];
  const activity = (message: HomeMessage, entry?: HomeEntry) => {
    const turn = turns.get(message.id);
    const status = homeStatus(message, entry, turn);
    const waiting = dependencies(data, turn);
    return {
      detail: {
        routing: "Routing…", queued: waiting ? `Waiting for ${waiting}` : "Queued",
        working: progress.get(message.id) || "Working…", ready: "", failed: "Failed",
        interrupted: "Stopped", cancelled: "Cancelled",
      }[status],
    };
  };
  for (const message of data.messages) {
    if (message.reaction || edited.has(message.id)) continue;
    const entry = message.entryId ? entries.get(message.entryId) : undefined;
    const status = activity(message, entry);
    rows.push({
      id: message.id, text: message.text, role: "You", createdAt: message.createdAt,
      sessionId: entry?.sessionId, title: entry?.title, quote: replyTarget(feed, message.replyToId),
      replyable: !!entry?.sessionId, ...status,
    });
  }
  const reactions = new Map(data.messages.filter(message => message.reaction).map(message => [message.replyToId, message]));
  for (const entry of data.entries) for (const update of entry.updates) {
    const source = sources.get(update.sourceId || entry.sourceId);
    if (update.kind === "progress" || !source || edited.has(source.id)) continue;
    const reaction = reactions.get(update.id);
    rows.push({
      id: update.id, role: "Agent", text: update.text, createdAt: update.createdAt,
      sessionId: entry.sessionId, title: entry.title, replyable: !!entry.sessionId,
      quote: update.quoteSource ? source.reaction ? replyTarget(feed, source.replyToId)
        : { id: source.id, role: "You", text: source.text } : undefined,
      detail: reaction ? activity(reaction, entry).detail : undefined,
    });
  }
  return rows.sort((a, b) => a.createdAt.localeCompare(b.createdAt));
}

export function conversationRows(feed: Feed): Row[] {
  if (feed.view === "home") return homeRows(feed);
  const rows: Row[] = (feed.conversation?.messages ?? []).filter(message => !message.reaction).map(message => ({
    id: message.id, role: message.role === "user" ? "You" : "Agent", text: message.text,
    sessionId: feed.view, replyable: message.role === "assistant" && message.replyable,
    quote: message.request ? { id: message.id, role: "You", text: message.request } : undefined,
  }));
  for (const turn of sessionTurns(feed)) {
    const progress = turn.sourceId && feed.progress.get(turn.sourceId);
    if (turn.status === "running" && progress) rows.push({
      id: `progress:${turn.id}`, role: "Agent", text: progress,
      quote: { id: turn.id, role: "You", text: turn.text },
    });
  }
  if (feed.conversation?.streaming && !rows.some(row => row.id.startsWith("progress:"))) {
    rows.push({ id: "streaming", role: "Agent", text: feed.conversation.streaming });
  }
  return rows;
}

export function queuedRows(feed: Feed) {
  if (feed.view === "home") return [];
  return sessionTurns(feed).filter(turn => turn.status === "queued").map(turn => {
    const waiting = dependencies(feed.data, turn);
    return {
      text: feed.data.messages.find(message => message.id === turn.sourceId)?.reaction ? "👍 Go ahead" : turn.text,
      detail: waiting ? `Waiting for ${waiting}` : "Queued",
    };
  });
}
