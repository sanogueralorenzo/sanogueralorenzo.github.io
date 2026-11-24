import type { Data, HomeEntry, HomeMessage, Turn } from "../src/state.ts";
import type { Conversation } from "./api.ts";

export type Target = { id: string; text: string; sessionId?: string | null };
export type Row = Target & {
  role: "You" | "Agent";
  title?: string;
  detail?: string;
  quote?: string;
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

function requestQuotes(messages: HomeMessage[], entries: HomeEntry[], edited: Set<string | undefined>) {
  const replies = new Map(entries.flatMap(entry => entry.updates.map(update => [update.id, {
    text: update.text, sourceId: update.sourceId || entry.sourceId, createdAt: update.createdAt,
  }] as const)));
  const older = new Map<string, { newerAt: string; text?: string }>();
  let newerAt: string | undefined;
  for (const message of [...messages].reverse()) {
    if (newerAt) older.set(message.id, {
      newerAt, text: message.reaction && message.replyToId ? replies.get(message.replyToId)?.text : message.text,
    });
    if (!message.reaction && !edited.has(message.id)) newerAt = message.createdAt;
  }
  function quote(sourceId?: string, answeredAt?: string) {
    const prior = sourceId ? older.get(sourceId) : undefined;
    return prior && (!answeredAt || prior.newerAt <= answeredAt) ? prior.text : undefined;
  }
  return { replies, quote };
}

function homeRows(feed: Feed): Row[] {
  const { data, progress } = feed;
  const edited = new Set(data.messages.map(message => message.editOfId));
  const entries = new Map(data.entries.map(entry => [entry.id, entry]));
  const sources = new Map(data.messages.map(message => [message.id, message]));
  const turns = new Map(data.turns.map(turn => [turn.sourceId, turn]));
  const { replies, quote } = requestQuotes(data.messages, data.entries, edited);
  const rows: (Row & { createdAt: string; replyToId?: string })[] = [];
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
      sessionId: entry?.sessionId, replyToId: message.replyToId,
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
      quote: quote(source.id, update.createdAt),
      detail: reaction ? activity(reaction, entry).detail : undefined,
    });
  }
  return rows.sort((a, b) => a.createdAt.localeCompare(b.createdAt)).map(({ replyToId, ...row }, index) => ({
    ...row, quote: replyToId && rows[index - 1]?.id !== replyToId
      ? sources.get(replyToId)?.text ?? replies.get(replyToId)?.text : row.quote,
  }));
}

export function conversationRows(feed: Feed): Row[] {
  if (feed.view === "home") return homeRows(feed);
  const entries = feed.data.entries.filter(entry => entry.sessionId === feed.view);
  const entryIds = new Set(entries.map(entry => entry.id));
  const requests = feed.data.messages.filter(message => message.entryId && entryIds.has(message.entryId));
  const { replies, quote } = requestQuotes(requests, entries, new Set(requests.map(message => message.editOfId)));
  const messages = (feed.conversation?.messages ?? []).filter(message => !message.reaction);
  const rows: Row[] = messages.map(message => {
    const reply = replies.get(message.id);
    return {
      id: message.id, role: message.role === "user" ? "You" : "Agent", text: message.text,
      sessionId: feed.view, replyable: message.role === "assistant" && message.replyable,
      quote: quote(reply?.sourceId, reply?.createdAt),
    };
  });
  for (const turn of sessionTurns(feed)) {
    const progress = turn.sourceId && feed.progress.get(turn.sourceId);
    if (turn.status === "running" && progress) rows.push({
      id: `progress:${turn.id}`, role: "Agent", text: progress,
      quote: quote(turn.sourceId),
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
