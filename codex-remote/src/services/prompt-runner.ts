import {
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
  requestApprovalFromTelegram: (ctx: PromptContext, chatId: string, request: ApprovalRequest) => Promise<ApprovalDecision>;
};

const TELEGRAM_MESSAGE_LIMIT = 4096;
const TELEGRAM_MESSAGE_CHUNK = 3900;

export function createPromptRunner(deps: PromptRunnerDeps) {
  async function runPromptThroughCodex(ctx: PromptContext, chatId: string, text: string): Promise<void> {
    const threadId = await deps.store.get(chatId);
    const runtimeOptions = {
      approvalHandler: (request: ApprovalRequest) => deps.requestApprovalFromTelegram(ctx, chatId, request)
    };
    const finalizeTurn = async (turn: TimedTurnLike): Promise<void> => {
      await replyFromTimedTurn(ctx, turn);
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
        await recoverFromUnavailableThread(ctx, chatId, text, runtimeOptions);
        return;
      }
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      await ctx.reply(formatFailure("Codex error.", message));
    }
  }

  async function replyFromTimedTurn(ctx: PromptContext, turn: TimedTurnLike): Promise<void> {
    if (turn.status === "completed") {
      await replyCompletedOutput(ctx, turn.response);
      return;
    }

    queueBackgroundReply((message) => ctx.api.sendMessage(ctx.chat.id, message), turn.completion);
  }

  async function recoverFromUnavailableThread(
    ctx: PromptContext,
    chatId: string,
    text: string,
    runtimeOptions: {
      approvalHandler: (request: ApprovalRequest) => Promise<ApprovalDecision>;
    }
  ): Promise<void> {
    const options = deps.getConversationOptions();
    const initialized = await createAndSendFirstMessageWithTimeoutContinuation(options, text, runtimeOptions);
    await deps.bindChatToThread(chatId, initialized.conversationId);

    if (initialized.status === "completed") {
      await replyCompletedOutput(ctx, initialized.response);
      return;
    }

    queueBackgroundReply((message) => ctx.api.sendMessage(ctx.chat.id, message), initialized.completion);
  }

  function queueBackgroundReply(
    sender: (text: string) => Promise<unknown>,
    completion: Promise<{ response: string }>
  ): void {
    void completion
      .then(async ({ response }) => {
        const output = response?.trim() ? response : "(Empty Codex response)";
        await sendTextChunks(sender, output);
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

async function replyCompletedOutput(ctx: PromptContext, response: string): Promise<void> {
  const output = response || "(Empty Codex response)";
  await sendTextChunks((message) => ctx.reply(message), output);
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
