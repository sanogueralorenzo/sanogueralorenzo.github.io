import { InputFile } from "grammy";
import type {
  ApprovalDecision,
  ApprovalPolicy,
  ApprovalRequest,
  SandboxMode,
  TurnCompletion,
  UserInputAnswers,
  UserInputRequest,
} from "../adapters/app-server/client.js";
import {
  createAndSendFirstMessageWithTimeoutContinuation,
  sendMessageWithoutResumeWithTimeoutContinuation,
  sendMessageWithTimeoutContinuation,
} from "../adapters/app-server/client.js";
import { BindingStore } from "../adapters/binding-store.js";
import { formatFailure } from "../bot/messages.js";
import { PromptContext } from "../bot/context.js";
import { sendTextChunks } from "../shared/telegram-text.js";

const CODEXBOT_FINAL_INSTRUCTION = "Be concise; include outcome, validation, blockers if relevant; no extra explanation unless asked.";

type ConversationOptions = {
  cwd: string;
  model?: string;
  approvalPolicy?: ApprovalPolicy;
  sandboxMode?: SandboxMode;
  networkAccessEnabled?: boolean | null;
  skipGitRepoCheck?: boolean | null;
};

type TimedTurnLike =
  | { status: "completed"; response: string; imagePaths?: string[] }
  | { status: "timed_out"; completion: Promise<TurnCompletion> };

type PromptTurnRuntimeOptions = {
  approvalHandler: (request: ApprovalRequest) => Promise<ApprovalDecision>;
  requestUserInputHandler: (request: UserInputRequest) => Promise<UserInputAnswers>;
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
  requestUserInputFromTelegram?: (ctx: PromptContext, chatId: string, request: UserInputRequest) => Promise<UserInputAnswers>;
};

export function createPromptRunner(deps: PromptRunnerDeps) {
  const threadTurnLocks = new Map<string, Promise<unknown>>();

  async function runPromptThroughCodex(ctx: PromptContext, chatId: string, text: string): Promise<void> {
    const threadId = await deps.store.get(chatId);
    const finalOutputRelay = createFinalOutputRelay(
      (message) => ctx.api.sendMessage(ctx.chat.id, message),
      (path) => ctx.api.sendPhoto(ctx.chat.id, new InputFile(path))
    );
    const runtimeOptions: PromptTurnRuntimeOptions = {
      approvalHandler: (request: ApprovalRequest) => deps.requestApprovalFromTelegram(ctx, chatId, request),
      requestUserInputHandler: (request: UserInputRequest) =>
        deps.requestUserInputFromTelegram?.(ctx, chatId, request) ?? Promise.resolve({}),
    };
    const finalizeTurn = async (turn: TimedTurnLike): Promise<void> => {
      await replyFromTimedTurn(turn, finalOutputRelay, async (completion) => completion);
    };

    try {
      if (!threadId) {
        if (deps.pendingNewSessionChats.has(chatId)) {
          const options = deps.getConversationOptions();
          const selectedCwd = deps.getPendingNewSessionCwd(chatId);
          if (selectedCwd) {
            options.cwd = selectedCwd;
          }
          const initialized = await createAndSendFirstMessageWithTimeoutContinuation(
            options,
            withCodexbotFinalInstruction(text),
            runtimeOptions
          );
          await deps.bindChatToThread(chatId, initialized.threadId);
          deps.pendingNewSessionChats.delete(chatId);
          deps.clearPendingNewSessionCwd(chatId);
          await finalizeTurn(initialized);
          return;
        }

        await deps.onThreadNotBound(ctx, chatId);
        return;
      }

      await withThreadTurnLock(threadId, async () => {
        try {
          const turn = await sendMessageWithTimeoutContinuation(
            threadId,
            withCodexbotFinalInstruction(text),
            runtimeOptions
          );
          await finalizeTurn(turn);
          return;
        } catch (error) {
          if (!isNoRolloutFoundError(error)) {
            throw error;
          }
        }

        try {
          const firstTurn = await sendMessageWithoutResumeWithTimeoutContinuation(
            threadId,
            withCodexbotFinalInstruction(text),
            runtimeOptions
          );
          await finalizeTurn(firstTurn);
          return;
        } catch {
          await recoverFromUnavailableThread(chatId, text, runtimeOptions, finalOutputRelay);
          return;
        }
      });
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      await ctx.reply(formatFailure("Codex error.", message));
    }
  }

  async function withThreadTurnLock<T>(threadId: string, work: () => Promise<T>): Promise<T> {
    const previous = threadTurnLocks.get(threadId) ?? Promise.resolve();
    const current = previous.then(async () => work());
    const safeCurrent = current.catch(() => undefined);
    threadTurnLocks.set(threadId, safeCurrent);

    try {
      return await current;
    } finally {
      if (threadTurnLocks.get(threadId) === safeCurrent) {
        threadTurnLocks.delete(threadId);
      }
    }
  }

  async function replyFromTimedTurn(
    turn: TimedTurnLike,
    finalOutputRelay: FinalOutputRelay,
    prepareCompletion: (completion: TurnCompletion) => Promise<TurnCompletion>
  ): Promise<void> {
    const completion = turn.status === "completed"
      ? completionFromCompletedTurn(turn)
      : await turn.completion;
    await finalOutputRelay.send(await prepareCompletion(completion));
  }

  async function recoverFromUnavailableThread(
    chatId: string,
    text: string,
    runtimeOptions: PromptTurnRuntimeOptions,
    finalOutputRelay: FinalOutputRelay
  ): Promise<void> {
    const options = deps.getConversationOptions();
    const initialized = await createAndSendFirstMessageWithTimeoutContinuation(
      options,
      withCodexbotFinalInstruction(text),
      runtimeOptions
    );
    await deps.bindChatToThread(chatId, initialized.threadId);

    if (initialized.status === "completed") {
      await finalOutputRelay.send(completionFromCompletedTurn(initialized));
      return;
    }

    await finalOutputRelay.send(await initialized.completion);
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

function withCodexbotFinalInstruction(text: string): string {
  return `${text}\n\n${CODEXBOT_FINAL_INSTRUCTION}`;
}

type FinalOutputRelay = {
  send: (completion: TurnCompletion) => Promise<void>;
};

const EMPTY_CODEX_RESPONSE = "(Empty Codex response)";

function completionFromCompletedTurn(turn: { response: string; imagePaths?: string[] }): TurnCompletion {
  return {
    response: turn.response,
    imagePaths: turn.imagePaths ?? [],
  };
}

function createFinalOutputRelay(
  sender: (text: string) => Promise<unknown>,
  imageSender: (path: string) => Promise<unknown>
): FinalOutputRelay {
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

  const send = async (completion: TurnCompletion): Promise<void> => {
    const output = completion.response?.trim() ? completion.response : EMPTY_CODEX_RESPONSE;
    await queueMessage(output);
    for (const path of completion.imagePaths ?? []) {
      try {
        await imageSender(path);
      } catch {
        await queueMessage(`Image generated but Telegram upload failed:\n${path}`);
      }
    }
  };

  return {
    send
  };
}
