import {
  ApprovalDecision,
  ApprovalPolicy,
  ApprovalRequest,
  SandboxMode,
  TurnProgressEvent,
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
  onTurnEvent: (event: TurnProgressEvent) => void;
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
    const progressRelay = createTurnProgressRelay((message) => ctx.api.sendMessage(ctx.chat.id, message));
    const runtimeOptions: PromptTurnRuntimeOptions = {
      approvalHandler: (request: ApprovalRequest) => deps.requestApprovalFromTelegram(ctx, chatId, request),
      onTurnEvent: (event) => {
        progressRelay.onTurnEvent(event);
      }
    };
    const finalizeTurn = async (turn: TimedTurnLike): Promise<void> => {
      await replyFromTimedTurn(turn, progressRelay);
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
        await recoverFromUnavailableThread(chatId, text, runtimeOptions, progressRelay);
        return;
      }
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      await ctx.reply(formatFailure("Codex error.", message));
    }
  }

  async function replyFromTimedTurn(turn: TimedTurnLike, progressRelay: TurnProgressRelay): Promise<void> {
    if (turn.status === "completed") {
      await progressRelay.sendFinalOutput(turn.response);
      return;
    }

    progressRelay.queueFinalOutput(turn.completion);
  }

  async function recoverFromUnavailableThread(
    chatId: string,
    text: string,
    runtimeOptions: PromptTurnRuntimeOptions,
    progressRelay: TurnProgressRelay
  ): Promise<void> {
    const options = deps.getConversationOptions();
    const initialized = await createAndSendFirstMessageWithTimeoutContinuation(options, text, runtimeOptions);
    await deps.bindChatToThread(chatId, initialized.threadId);

    if (initialized.status === "completed") {
      await progressRelay.sendFinalOutput(initialized.response);
      return;
    }

    progressRelay.queueFinalOutput(initialized.completion);
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

type TurnProgressRelay = {
  onTurnEvent: (event: TurnProgressEvent) => void;
  sendFinalOutput: (response: string) => Promise<void>;
  queueFinalOutput: (completion: Promise<{ response: string }>) => void;
};

const EMPTY_CODEX_RESPONSE = "(Empty Codex response)";

function createTurnProgressRelay(sender: (text: string) => Promise<unknown>): TurnProgressRelay {
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

  const onTurnEvent = (_event: TurnProgressEvent): void => {
    // Intentionally ignore intermediate deltas/events.
    // Telegram should receive only the final turn output.
  };

  const sendFinalOutput = async (response: string): Promise<void> => {
    const output = response?.trim() ? response : EMPTY_CODEX_RESPONSE;
    await queueMessage(output);
  };

  const queueFinalOutput = (completion: Promise<{ response: string }>): void => {
    void completion
      .then(async ({ response }) => {
        await sendFinalOutput(response);
      })
      .catch(async (error) => {
        const message = error instanceof Error ? error.message : String(error);
        await queueMessage(`Codex error: ${message}`);
      })
      .catch(() => undefined);
  };

  return {
    onTurnEvent,
    sendFinalOutput,
    queueFinalOutput
  };
}
