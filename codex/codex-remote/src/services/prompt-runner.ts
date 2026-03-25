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
import { sendTextChunks } from "../shared/telegram-text.js";

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

type PromptTurnRuntimeOptions = {
  approvalHandler: (request: ApprovalRequest) => Promise<ApprovalDecision>;
};

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

export function createPromptRunner(deps: PromptRunnerDeps) {
  async function runPromptThroughCodex(ctx: PromptContext, chatId: string, text: string): Promise<void> {
    const threadId = await deps.store.get(chatId);
    const finalOutputRelay = createFinalOutputRelay((message) => ctx.api.sendMessage(ctx.chat.id, message));
    const runtimeOptions: PromptTurnRuntimeOptions = {
      approvalHandler: (request: ApprovalRequest) => deps.requestApprovalFromTelegram(ctx, chatId, request),
    };
    const finalizeTurn = async (turn: TimedTurnLike): Promise<void> => {
      await replyFromTimedTurn(turn, finalOutputRelay);
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
          await deps.bindChatToThread(chatId, initialized.threadId);
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
        await recoverFromUnavailableThread(chatId, text, runtimeOptions, finalOutputRelay);
        return;
      }
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      await ctx.reply(formatFailure("Codex error.", message));
    }
  }

  async function replyFromTimedTurn(turn: TimedTurnLike, finalOutputRelay: FinalOutputRelay): Promise<void> {
    if (turn.status === "completed") {
      await finalOutputRelay.send(turn.response);
      return;
    }

    finalOutputRelay.queue(turn.completion);
  }

  async function recoverFromUnavailableThread(
    chatId: string,
    text: string,
    runtimeOptions: PromptTurnRuntimeOptions,
    finalOutputRelay: FinalOutputRelay
  ): Promise<void> {
    const options = deps.getConversationOptions();
    const initialized = await createAndSendFirstMessageWithTimeoutContinuation(options, text, runtimeOptions);
    await deps.bindChatToThread(chatId, initialized.threadId);

    if (initialized.status === "completed") {
      await finalOutputRelay.send(initialized.response);
      return;
    }

    finalOutputRelay.queue(initialized.completion);
  }

  return {
    runPromptThroughCodex
  };
}

function isNoRolloutFoundError(error: unknown): boolean {
  if (!(error instanceof Error)) {
    return false;
  }
  return error.message.includes("no rollout found for thread id");
}

type FinalOutputRelay = {
  send: (response: string) => Promise<void>;
  queue: (completion: Promise<{ response: string }>) => void;
};

const EMPTY_CODEX_RESPONSE = "(Empty Codex response)";

function createFinalOutputRelay(sender: (text: string) => Promise<unknown>): FinalOutputRelay {
  let sendQueue = Promise.resolve();

  const queueMessage = (text: string): Promise<void> => {
    const payload = text.trim();
    if (!payload) {
      return sendQueue;
    }

    sendQueue = sendQueue
      .then(async () => {
        await sendTextChunks(sender, payload);
      })
      .catch(() => undefined);
    return sendQueue;
  };

  const send = async (response: string): Promise<void> => {
    const output = response?.trim() ? response : EMPTY_CODEX_RESPONSE;
    await queueMessage(output);
  };

  const queue = (completion: Promise<{ response: string }>): void => {
    void completion
      .then(async ({ response }) => {
        await send(response);
      })
      .catch(async (error) => {
        const message = error instanceof Error ? error.message : String(error);
        await queueMessage(`Codex error: ${message}`);
      })
      .catch(() => undefined);
  };

  return {
    send,
    queue
  };
}
