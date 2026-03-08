import {
  AgentTextSnapshot,
  ApprovalDecision,
  ApprovalPolicy,
  ApprovalRequest,
  SandboxMode,
  createAndSendFirstMessageWithTimeoutContinuation,
  sendMessageWithoutResumeWithTimeoutContinuation,
  sendMessageWithTimeoutContinuation
} from "../adapters/app-server-client.js";
import { BindingStore } from "../adapters/binding-store.js";
import { formatFailure } from "../bot/messages.js";
import { PromptContext } from "../bot/context.js";
import { createTelegramDraftStreamer, TelegramDraftStreamer } from "./telegram-draft-streamer.js";

type ConversationOptions = {
  cwd: string;
  model?: string;
  approvalPolicy?: ApprovalPolicy;
  sandboxMode?: SandboxMode;
  networkAccessEnabled?: boolean | null;
  skipGitRepoCheck?: boolean | null;
};

type TimedTurnLike =
  | { status: "completed"; response: string }
  | { status: "timed_out"; completion: Promise<{ response: string }> };

type PromptRunnerDeps = {
  store: BindingStore;
  pendingNewSessionChats: Set<string>;
  getPendingNewSessionCwd: (chatId: string) => string | null;
  clearPendingNewSessionCwd: (chatId: string) => void;
  onThreadNotBound: (ctx: PromptContext, chatId: string) => Promise<void>;
  getConversationOptions: () => ConversationOptions;
  bindChatToThread: (chatId: string, threadId: string) => Promise<void>;
  resolveThreadTitle: (threadId: string) => Promise<string>;
  requestApprovalFromTelegram: (ctx: PromptContext, chatId: string, request: ApprovalRequest) => Promise<ApprovalDecision>;
  enableDraftStreaming: boolean;
  draftStreamingThrottleMs: number;
};

const TELEGRAM_MESSAGE_LIMIT = 4096;
const TELEGRAM_MESSAGE_CHUNK = 3900;

export function createPromptRunner(deps: PromptRunnerDeps) {
  async function runPromptThroughCodex(ctx: PromptContext, chatId: string, text: string): Promise<void> {
    const draftSession = createDraftSession(ctx, deps.enableDraftStreaming, deps.draftStreamingThrottleMs);
    const threadId = await deps.store.get(chatId);
    const runtimeOptions = {
      approvalHandler: (request: ApprovalRequest) => deps.requestApprovalFromTelegram(ctx, chatId, request),
      onAgentTextSnapshot: (snapshot: AgentTextSnapshot) => {
        draftSession.pushSnapshot(snapshot);
      }
    };
    const finalizeTurn = async (turn: TimedTurnLike, delayedIntro = "Delayed:"): Promise<void> => {
      await draftSession.stop(true);
      await replyFromTimedTurn(ctx, turn, delayedIntro, draftSession.shouldSuppressFinalOutput);
    };

    try {
      if (!threadId) {
        if (deps.pendingNewSessionChats.has(chatId)) {
          const options = deps.getConversationOptions();
          const selectedCwd = deps.getPendingNewSessionCwd(chatId);
          if (selectedCwd) {
            options.cwd = selectedCwd;
          }
          const initialized = await createAndSendFirstMessageWithTimeoutContinuation(options, text, runtimeOptions);
          await deps.bindChatToThread(chatId, initialized.conversationId);
          deps.pendingNewSessionChats.delete(chatId);
          deps.clearPendingNewSessionCwd(chatId);
          await finalizeTurn(initialized);
          return;
        }

        await draftSession.stop(false);
        await deps.onThreadNotBound(ctx, chatId);
        return;
      }

      try {
        const turn = await sendMessageWithTimeoutContinuation(threadId, text, runtimeOptions);
        await finalizeTurn(turn);
        return;
      } catch (error) {
        if (!isNoRolloutFoundError(error)) {
          throw error;
        }
      }

      try {
        const firstTurn = await sendMessageWithoutResumeWithTimeoutContinuation(threadId, text, runtimeOptions);
        await finalizeTurn(firstTurn);
        return;
      } catch {
        await draftSession.stop(true);
        await recoverFromUnavailableThread(ctx, chatId, text, runtimeOptions, draftSession.shouldSuppressFinalOutput);
        return;
      }
    } catch (error) {
      await draftSession.stop(false);
      const message = error instanceof Error ? error.message : String(error);
      await ctx.reply(formatFailure("Codex error.", message));
    }
  }

  async function replyFromTimedTurn(
    ctx: PromptContext,
    turn: TimedTurnLike,
    delayedIntro = "Delayed:",
    shouldSuppressFinalOutput: (text: string) => boolean
  ): Promise<void> {
    if (turn.status === "completed") {
      await replyCompletedOutput(ctx, turn.response, shouldSuppressFinalOutput);
      return;
    }

    await replyDelayedNotice(ctx);
    queueBackgroundReply((message) => ctx.api.sendMessage(ctx.chat.id, message), turn.completion, delayedIntro);
  }

  async function recoverFromUnavailableThread(
    ctx: PromptContext,
    chatId: string,
    text: string,
    runtimeOptions: {
      approvalHandler: (request: ApprovalRequest) => Promise<ApprovalDecision>;
      onAgentTextSnapshot: (snapshot: AgentTextSnapshot) => void;
    },
    shouldSuppressFinalOutput: (text: string) => boolean
  ): Promise<void> {
    const options = deps.getConversationOptions();
    const initialized = await createAndSendFirstMessageWithTimeoutContinuation(options, text, runtimeOptions);
    await deps.bindChatToThread(chatId, initialized.conversationId);

    const title = await deps.resolveThreadTitle(initialized.conversationId);
    if (initialized.status === "completed") {
      await replyCompletedOutput(ctx, initialized.response, shouldSuppressFinalOutput);
      return;
    }

    await replyDelayedNotice(ctx);
    queueBackgroundReply(
      (message) => ctx.api.sendMessage(ctx.chat.id, message),
      initialized.completion,
      `Delayed for "${title}":`
    );
  }

  function queueBackgroundReply(
    sender: (text: string) => Promise<unknown>,
    completion: Promise<{ response: string }>,
    intro: string
  ): void {
    void completion
      .then(async ({ response }) => {
        const output = response?.trim() ? response : "(Empty Codex response)";
        await sendTextChunks(sender, `${intro}\n\n${output}`);
      })
      .catch(async (error) => {
        const message = error instanceof Error ? error.message : String(error);
        await sender(`Codex error: ${message}`);
      })
      .catch(() => undefined);
  }

  return {
    runPromptThroughCodex
  };
}

function createDraftSession(ctx: PromptContext, enabled: boolean, throttleMs: number): {
  pushSnapshot: (snapshot: AgentTextSnapshot) => void;
  stop: (flushPending: boolean) => Promise<void>;
  shouldSuppressFinalOutput: (text: string) => boolean;
} {
  const streamersByItemId = new Map<string, TelegramDraftStreamer>();
  const usedDraftIds = new Set<number>();
  const turnSeed = `${Date.now().toString(36)}-${Math.random().toString(36).slice(2)}`;
  const messageThreadId = getMessageThreadId(ctx);
  let latestAgentItemId: string | null = null;
  let latestDeliveredDraft: string | null = null;

  const getOrCreateStreamer = (itemId: string): TelegramDraftStreamer => {
    const existing = streamersByItemId.get(itemId);
    if (existing) {
      return existing;
    }

    const draftId = allocateDraftId(`${turnSeed}:${itemId}`, usedDraftIds);
    const streamer = createTelegramDraftStreamer({
      enabled,
      throttleMs,
      sendDraft: (snapshot) =>
        ctx.api.sendMessageDraft(
          ctx.chat.id,
          draftId,
          snapshot,
          messageThreadId === null ? undefined : { message_thread_id: messageThreadId }
        )
    });
    streamersByItemId.set(itemId, streamer);
    return streamer;
  };

  return {
    pushSnapshot: (snapshot: AgentTextSnapshot): void => {
      const itemId = snapshot.itemId.trim();
      if (!itemId) {
        return;
      }
      latestAgentItemId = itemId;
      getOrCreateStreamer(itemId).pushSnapshot(snapshot.text);
    },
    stop: async (flushPending: boolean): Promise<void> => {
      for (const streamer of streamersByItemId.values()) {
        await streamer.stop(flushPending);
      }

      if (!flushPending || !latestAgentItemId) {
        latestDeliveredDraft = null;
        return;
      }

      const latestText = streamersByItemId.get(latestAgentItemId)?.lastDeliveredDraft()?.trim();
      latestDeliveredDraft = latestText && latestText.length > 0 ? latestText : null;
    },
    shouldSuppressFinalOutput: (text: string): boolean => {
      const normalized = text.trim();
      return normalized.length > 0 && latestDeliveredDraft !== null && normalized === latestDeliveredDraft;
    }
  };
}

async function replyCompletedOutput(
  ctx: PromptContext,
  response: string,
  shouldSuppressFinalOutput: (text: string) => boolean
): Promise<void> {
  const output = response || "(Empty Codex response)";
  if (shouldSuppressFinalOutput(output)) {
    return;
  }
  await sendTextChunks((message) => ctx.reply(message), output);
}

async function replyDelayedNotice(ctx: PromptContext): Promise<void> {
  await ctx.reply("Still working, I will send a message when ready");
}

async function sendTextChunks(sender: (text: string) => Promise<unknown>, text: string): Promise<void> {
  const chunks = splitTextForTelegram(text);
  for (const chunk of chunks) {
    await sender(chunk);
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

function isNoRolloutFoundError(error: unknown): boolean {
  if (!(error instanceof Error)) {
    return false;
  }
  return error.message.includes("no rollout found for thread id");
}

function getMessageThreadId(ctx: PromptContext): number | null {
  const threadId = ctx.message?.message_thread_id;
  return typeof threadId === "number" ? threadId : null;
}

function allocateDraftId(seed: string, usedDraftIds: Set<number>): number {
  let hash = 2166136261;
  for (let index = 0; index < seed.length; index += 1) {
    hash ^= seed.charCodeAt(index);
    hash = Math.imul(hash, 16777619);
  }

  let candidate = (hash >>> 1) || 1;
  while (usedDraftIds.has(candidate)) {
    candidate = candidate >= 2_147_483_646 ? 1 : candidate + 1;
  }

  usedDraftIds.add(candidate);
  return candidate;
}
