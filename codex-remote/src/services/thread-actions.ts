import { basename } from "node:path";
import {
  ThreadSummary,
  findThreadById,
  listThreads
} from "../adapters/app-server-client.js";
import { BindingStore } from "../adapters/binding-store.js";
import {
  deleteSessionByThreadId,
  listSessionsForSelection,
  loadDesktopThreadTitles,
  loadLatestAssistantMessageByThreadId
} from "../adapters/codex-sessions.js";
import {
  buildFolderSelectionLabels,
  buildThreadSelectionLabels,
  newFolderSelectionKeyboard,
  parseSelectionFromOptions,
  quickActionsKeyboard,
  threadSelectionKeyboard
} from "../bot/keyboards.js";
import { cleanPreview, formatActionTitle, formatFolderLabel } from "../bot/messages.js";
import { ReplyFn } from "../bot/context.js";
import { ActionName } from "../shared/actions.js";

export type ListedThread = {
  id: string;
  title: string;
  folder: string;
  cwd: string;
  lastUpdatedAt: string;
};
export type ListedFolderChoice = {
  cwd: string;
  label: string;
};

const TELEGRAM_MESSAGE_LIMIT = 4096;
const TELEGRAM_MESSAGE_CHUNK = 3900;

type ThreadActionsDeps = {
  codexHome: string;
  defaultThreadsLimit: number;
  store: BindingStore;
  pendingNewSessionChats: Set<string>;
  pendingNewSessionCwds: Map<string, string>;
  lastListedSessions: Map<string, ListedThread[]>;
  lastListedSessionModes: Map<string, "resume" | "delete">;
  lastListedFolderChoices: Map<string, ListedFolderChoice[]>;
  resolveDefaultCwd: () => string;
  bindChatToThread: (chatId: string, threadId: string) => Promise<void>;
};

export function createThreadActions(deps: ThreadActionsDeps) {
  async function executeAction(chatId: string, action: ActionName, reply: ReplyFn): Promise<void> {
    if (action === "new") {
      await replyFolderChoices(chatId, reply);
      return;
    }

    if (action === "resume") {
      await replyThreadsList(chatId, deps.defaultThreadsLimit, reply, "resume");
      return;
    }

    await replyThreadsList(chatId, deps.defaultThreadsLimit, reply, "delete");
  }

  async function pickThreadByIndex(chatId: string, index: number, reply: ReplyFn): Promise<void> {
    const selected = getListedSessionForIndex(chatId, index);
    if (!selected) {
      return;
    }

    deps.pendingNewSessionChats.delete(chatId);
    deps.pendingNewSessionCwds.delete(chatId);
    deps.lastListedSessions.delete(chatId);
    deps.lastListedSessionModes.delete(chatId);
    deps.lastListedFolderChoices.delete(chatId);
    await deps.bindChatToThread(chatId, selected.id);
    await reply(formatActionTitle("Resumed", selected.title), { reply_markup: quickActionsKeyboard() });

    const latestMessage = await loadLatestAssistantMessageByThreadId(selected.id, deps.codexHome);
    if (latestMessage) {
      await sendTextChunks(reply, `Latest message:\n\n${latestMessage}`);
    }
  }

  async function deleteThreadByIndex(chatId: string, index: number, reply: ReplyFn): Promise<void> {
    const selected = getListedSessionForIndex(chatId, index);
    if (!selected) {
      return;
    }

    const result = await deleteSessionByThreadId(selected.id, deps.codexHome);
    const boundId = await deps.store.get(chatId);

    deps.lastListedSessions.delete(chatId);
    deps.lastListedSessionModes.delete(chatId);
    deps.lastListedFolderChoices.delete(chatId);

    if (boundId === selected.id) {
      deps.pendingNewSessionChats.add(chatId);
      deps.pendingNewSessionCwds.set(chatId, selected.cwd || deps.resolveDefaultCwd());
      await deps.store.remove(chatId);
    }

    if (result.deleted) {
      if (boundId === selected.id) {
        await reply(`${formatActionTitle("Deleted", selected.title)}\n\nSend a message to start a new thread.`, {
          reply_markup: quickActionsKeyboard()
        });
      } else {
        await reply(formatActionTitle("Deleted", selected.title), { reply_markup: quickActionsKeyboard() });
      }
    }
  }

  async function pickFolderChoiceByIndex(chatId: string, index: number, reply: ReplyFn): Promise<void> {
    const selected = getListedFolderChoiceForIndex(chatId, index);
    if (!selected) {
      return;
    }

    await clearChatBindingState(chatId);
    deps.pendingNewSessionChats.add(chatId);
    deps.pendingNewSessionCwds.set(chatId, selected.cwd);
    deps.lastListedSessions.delete(chatId);
    deps.lastListedSessionModes.delete(chatId);
    deps.lastListedFolderChoices.delete(chatId);
    await reply(`New: Send message\nFolder: ${selected.label}`, { reply_markup: quickActionsKeyboard() });
  }

  async function resolveThreadTitle(threadId: string): Promise<string> {
    const desktopTitles = await loadDesktopThreadTitles(deps.codexHome);
    const desktopTitle = desktopTitles.get(threadId);
    if (desktopTitle) {
      return desktopTitle;
    }

    const match = await findThreadById(threadId, 800);
    if (match?.preview) {
      return cleanPreview(match.preview);
    }

    return "Untitled thread";
  }

  async function replyThreadsList(
    chatId: string,
    limit: number,
    reply: ReplyFn,
    mode: "resume" | "delete"
  ): Promise<void> {
    const sessions = await listSessionsForSelection(deps.codexHome, limit);
    if (!sessions.length) {
      await reply("No Codex sessions found.");
      return;
    }

    deps.lastListedSessions.set(chatId, sessions);
    deps.lastListedSessionModes.set(chatId, mode);
    deps.lastListedFolderChoices.delete(chatId);

    const prompt = mode === "delete" ? "Choose thread to delete" : "Choose thread";
    await reply(prompt, {
      reply_markup: threadSelectionKeyboard(
        sessions.map((session) => formatSessionSelectionLabel(session)),
        { includeNewButton: false }
      )
    });
  }

  async function replyFolderChoices(chatId: string, reply: ReplyFn): Promise<void> {
    deps.pendingNewSessionChats.delete(chatId);
    deps.pendingNewSessionCwds.delete(chatId);
    const threads = await listThreads(Math.max(80, deps.defaultThreadsLimit));
    const folderChoices = listFolderChoices(threads, deps.resolveDefaultCwd()).slice(0, 12);

    deps.lastListedSessions.delete(chatId);
    deps.lastListedSessionModes.delete(chatId);
    deps.lastListedFolderChoices.set(chatId, folderChoices);

    await reply("Choose folder", {
      reply_markup: newFolderSelectionKeyboard(folderChoices.map((choice) => choice.label))
    });
  }

  async function tryPickThreadByText(chatId: string, text: string, reply: ReplyFn): Promise<boolean> {
    const listed = deps.lastListedSessions.get(chatId);
    if (!listed || listed.length === 0) {
      return false;
    }

    const optionLabels = buildThreadSelectionLabels(listed.map((session) => session.title));
    const index = parseSelectionFromOptions(text, optionLabels);
    if (!index) {
      return false;
    }

    const mode = deps.lastListedSessionModes.get(chatId) ?? "resume";
    if (mode === "delete") {
      await deleteThreadByIndex(chatId, index, reply);
      return true;
    }

    await pickThreadByIndex(chatId, index, reply);
    return true;
  }

  async function tryPickFolderChoiceByText(chatId: string, text: string, reply: ReplyFn): Promise<boolean> {
    const listed = deps.lastListedFolderChoices.get(chatId);
    if (!listed || listed.length === 0) {
      return false;
    }

    const optionLabels = buildFolderSelectionLabels(listed.map((choice) => choice.label));
    const index = parseSelectionFromOptions(text, optionLabels);
    if (!index) {
      return false;
    }

    await pickFolderChoiceByIndex(chatId, index, reply);
    return true;
  }

  async function clearChatBindingState(chatId: string): Promise<void> {
    deps.lastListedSessions.delete(chatId);
    deps.lastListedSessionModes.delete(chatId);
    deps.lastListedFolderChoices.delete(chatId);
    deps.pendingNewSessionCwds.delete(chatId);
    await deps.store.remove(chatId);
  }

  function getListedSessionForIndex(chatId: string, index: number): ListedThread | null {
    const listed = deps.lastListedSessions.get(chatId);
    if (!listed || !listed.length) {
      return null;
    }
    if (index < 1 || index > listed.length) {
      return null;
    }
    return listed[index - 1];
  }

  function getListedFolderChoiceForIndex(chatId: string, index: number): ListedFolderChoice | null {
    const listed = deps.lastListedFolderChoices.get(chatId);
    if (!listed || !listed.length) {
      return null;
    }
    if (index < 1 || index > listed.length) {
      return null;
    }
    return listed[index - 1];
  }

  return {
    executeAction,
    pickThreadByIndex,
    pickFolderChoiceByIndex,
    tryPickThreadByText,
    tryPickFolderChoiceByText,
    resolveThreadTitle
  };
}

async function sendTextChunks(reply: ReplyFn, text: string): Promise<void> {
  const chunks = splitTextForTelegram(text);
  for (const chunk of chunks) {
    await reply(chunk);
  }
}

function splitTextForTelegram(text: string, maxLen = TELEGRAM_MESSAGE_CHUNK): string[] {
  if (text.length <= TELEGRAM_MESSAGE_LIMIT) {
    return [text];
  }

  const chunks: string[] = [];
  let remaining = text;
  while (remaining.length > maxLen) {
    let splitAt = remaining.lastIndexOf("\n", maxLen);
    if (splitAt < Math.floor(maxLen * 0.5)) {
      splitAt = remaining.lastIndexOf(" ", maxLen);
    }
    if (splitAt <= 0) {
      splitAt = maxLen;
    }

    const head = remaining.slice(0, splitAt).trimEnd();
    if (head) {
      chunks.push(head);
    }
    remaining = remaining.slice(splitAt).trimStart();
  }

  if (remaining) {
    chunks.push(remaining);
  }

  return chunks.length ? chunks : [""];
}

function listFolderChoices(threads: ThreadSummary[], defaultCwd: string): ListedFolderChoice[] {
  const byUpdateDesc = [...threads].sort((a, b) => b.updatedAt - a.updatedAt);
  const seen = new Set<string>();
  const choices: ListedFolderChoice[] = [];

  for (const thread of byUpdateDesc) {
    const cwd = (thread.cwd || "").trim();
    if (!cwd || seen.has(cwd)) {
      continue;
    }
    seen.add(cwd);
    choices.push({
      cwd,
      label: toFolderButtonLabel(cwd)
    });
  }

  if (!seen.has(defaultCwd)) {
    choices.unshift({
      cwd: defaultCwd,
      label: toFolderButtonLabel(defaultCwd)
    });
  }

  return choices;
}

function toFolderButtonLabel(cwd: string): string {
  const base = basename(cwd) || cwd;
  const formatted = formatFolderLabel(base);
  if (formatted.length <= 24) {
    return formatted;
  }
  return `${formatted.slice(0, 21)}...`;
}

function formatSessionSelectionLabel(session: ListedThread): string {
  const updated = formatUpdatedDate(session.lastUpdatedAt);
  return `${session.folder} | ${updated} | ${session.title}`;
}

function formatUpdatedDate(value: string): string {
  if (!value) {
    return "unknown";
  }
  if (value.length >= 10) {
    return value.slice(0, 10);
  }
  return value;
}
