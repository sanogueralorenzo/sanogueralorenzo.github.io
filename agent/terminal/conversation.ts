import type { Data, HomeEntry, HomeMessage, Turn } from "../src/state.ts";
import type { Conversation } from "./api.ts";

export type Target = { id: string; text: string; sessionId?: string | null };
export type Row = Target & {
  role: "You" | "Agent";
  title?: string;
  detail?: string;
  replyTo?: string;
  replyable?: boolean;
};
export type Feed = {
  data: Data;
  conversation?: Conversation;
  progress: Map<string, string>;
  view: string;
};

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
  const texts = new Map(data.messages.map(message => [message.id, message.text]));
  for (const entry of data.entries) for (const update of entry.updates) texts.set(update.id, update.text);
  const rows: (Row & { createdAt: string; sourceId?: string })[] = [];
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
      sessionId: entry?.sessionId, sourceId: message.replyToId,
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
      sourceId: source.reaction ? source.replyToId : source.id,
      detail: reaction ? activity(reaction, entry).detail : undefined,
    });
  }
  return rows.sort((a, b) => a.createdAt.localeCompare(b.createdAt)).map(({ sourceId, ...row }, index) => ({
    ...row, replyTo: sourceId && rows[index - 1]?.id !== sourceId ? texts.get(sourceId) : undefined,
  }));
}

export function conversationRows(feed: Feed): Row[] {
  if (feed.view === "home") return homeRows(feed);
  const messages = (feed.conversation?.messages ?? []).filter(message => !message.reaction);
  const rows: Row[] = messages.map((message, index) => {
    const preceding = messages[index - 1];
    return {
      id: message.id, role: message.role === "user" ? "You" : "Agent", text: message.text,
      sessionId: feed.view, replyable: message.role === "assistant" && message.replyable,
      replyTo: preceding?.role === "user" && preceding.text === message.request ? undefined : message.request,
    };
  });
  for (const turn of sessionTurns(feed)) {
    const progress = turn.sourceId && feed.progress.get(turn.sourceId);
    const preceding = rows.at(-1);
    if (turn.status === "running" && progress) rows.push({
      id: `progress:${turn.id}`, role: "Agent", text: progress,
      replyTo: preceding?.role === "You" && preceding.text === turn.text ? undefined : turn.text,
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
