import { basename } from "node:path";
import {
  ThreadSummary,
  listThreads
} from "../adapters/app-server-client.js";
import { BindingStore } from "../adapters/binding-store.js";
import {
  deleteSessionByThreadId,
  listSessionsForSelection,
  loadLatestAssistantMessageByThreadId
} from "../adapters/codex-core-sessions.js";
import {
  buildFolderSelectionLabels,
  buildThreadSelectionLabels,
  newFolderSelectionKeyboard,
  parseSelectionFromOptions,
  quickActionsKeyboard,
  threadSelectionKeyboard
} from "../bot/keyboards.js";
import { formatActionTitle, formatFolderLabel } from "../bot/messages.js";
import { ReplyFn } from "../bot/context.js";
import { ActionName } from "../shared/actions.js";
import { sendTextChunks } from "../shared/telegram-text.js";

export type ListedThread = {
  id: string;
  title: string;
  cwd: string;
};
export type ListedFolderChoice = {
  cwd: string;
  label: string;
};

type ThreadActionsDeps = {
  codexHome: string;
  defaultThreadsLimit: number;
  store: BindingStore;
  pendingNewSessionChats: Set<string>;
  pendingNewSessionCwds: Map<string, string>;
  selectionStateByChat: Map<string, ChatSelectionState>;
  resolveDefaultCwd: () => string;
  bindChatToThread: (chatId: string, threadId: string) => Promise<void>;
};

type ChatSelectionState = {
  sessions: ListedThread[];
  mode: "resume" | "delete";
  folderChoices: ListedFolderChoice[];
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

    clearPendingNewSessionState(chatId);
    clearListedSelectionState(chatId);
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
    const isDeletedThreadBound = boundId === selected.id;

    clearListedSelectionState(chatId);

    if (result.deleted) {
      if (isDeletedThreadBound) {
        deps.pendingNewSessionChats.add(chatId);
        deps.pendingNewSessionCwds.set(chatId, selected.cwd || deps.resolveDefaultCwd());
        await deps.store.remove(chatId);
      }

      if (isDeletedThreadBound) {
        await reply(`${formatActionTitle("Deleted", selected.title)}\n\nSend a message to start a new thread.`, {
          reply_markup: quickActionsKeyboard()
        });
      } else {
        await reply(formatActionTitle("Deleted", selected.title), { reply_markup: quickActionsKeyboard() });
      }
      return;
    }

    if (result.status === "skipped" && result.reason === "pinned") {
      await reply(
        `Skipped: ${selected.title}\n\nThis thread is pinned in Codex. Unpin it first, then delete again.`,
        { reply_markup: quickActionsKeyboard() }
      );
      return;
    }

    const details = result.message ? `\n\n${result.message}` : "";
    await reply(`Delete failed: ${selected.title}${details}`, { reply_markup: quickActionsKeyboard() });
  }

  async function pickFolderChoiceByIndex(chatId: string, index: number, reply: ReplyFn): Promise<void> {
    const selected = getListedFolderChoiceForIndex(chatId, index);
    if (!selected) {
      return;
    }

    await clearChatBindingState(chatId);
    deps.pendingNewSessionChats.add(chatId);
    deps.pendingNewSessionCwds.set(chatId, selected.cwd);
    await reply(`New: Send message\nFolder: ${selected.label}`, { reply_markup: quickActionsKeyboard() });
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

    deps.selectionStateByChat.set(chatId, {
      sessions,
      mode,
      folderChoices: []
    });

    const prompt = mode === "delete" ? "Choose thread to delete" : "Choose thread";
    const threadLabels = sessions.map((session) => session.title);
    await reply(prompt, {
      reply_markup: threadSelectionKeyboard(
        threadLabels,
        { includeNewButton: false }
      )
    });
  }

  async function replyFolderChoices(chatId: string, reply: ReplyFn): Promise<void> {
    clearPendingNewSessionState(chatId);
    const threads = await listThreads(Math.max(80, deps.defaultThreadsLimit));
    const folderChoices = listFolderChoices(threads, deps.resolveDefaultCwd()).slice(0, 12);

    clearListedSelectionState(chatId);
    deps.selectionStateByChat.set(chatId, {
      sessions: [],
      mode: "resume",
      folderChoices
    });

    await reply("Choose folder", {
      reply_markup: newFolderSelectionKeyboard(folderChoices.map((choice) => choice.label))
    });
  }

  async function tryPickThreadByText(chatId: string, text: string, reply: ReplyFn): Promise<boolean> {
    const state = deps.selectionStateByChat.get(chatId);
    if (!state || state.sessions.length === 0) {
      return false;
    }

    const optionLabels = buildThreadSelectionLabels(state.sessions.map((session) => session.title));
    const index = parseSelectionFromOptions(text, optionLabels);
    if (!index) {
      return false;
    }

    if (state.mode === "delete") {
      await deleteThreadByIndex(chatId, index, reply);
      return true;
    }

    await pickThreadByIndex(chatId, index, reply);
    return true;
  }

  async function tryPickFolderChoiceByText(chatId: string, text: string, reply: ReplyFn): Promise<boolean> {
    const state = deps.selectionStateByChat.get(chatId);
    if (!state || state.folderChoices.length === 0) {
      return false;
    }

    const optionLabels = buildFolderSelectionLabels(state.folderChoices.map((choice) => choice.label));
    const index = parseSelectionFromOptions(text, optionLabels);
    if (!index) {
      return false;
    }

    await pickFolderChoiceByIndex(chatId, index, reply);
    return true;
  }

  async function clearChatBindingState(chatId: string): Promise<void> {
    clearListedSelectionState(chatId);
    clearPendingNewSessionState(chatId);
    await deps.store.remove(chatId);
  }

  function clearPendingNewSessionState(chatId: string): void {
    deps.pendingNewSessionChats.delete(chatId);
    deps.pendingNewSessionCwds.delete(chatId);
  }

  function clearListedSelectionState(chatId: string): void {
    deps.selectionStateByChat.delete(chatId);
  }

  function getListedSessionForIndex(chatId: string, index: number): ListedThread | null {
    const listed = deps.selectionStateByChat.get(chatId)?.sessions;
    if (!listed || !listed.length) {
      return null;
    }
    if (index < 1 || index > listed.length) {
      return null;
    }
    return listed[index - 1];
  }

  function getListedFolderChoiceForIndex(chatId: string, index: number): ListedFolderChoice | null {
    const listed = deps.selectionStateByChat.get(chatId)?.folderChoices;
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
    tryPickFolderChoiceByText
  };
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
