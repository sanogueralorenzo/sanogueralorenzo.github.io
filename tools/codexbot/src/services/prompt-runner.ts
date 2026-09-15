import { InputFile } from "grammy";
import type {
  ApprovalDecision,
  ApprovalRequest,
  ApprovalPolicy,
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
import { TopicStore } from "../adapters/topic-store.js";
import { formatFailure } from "../bot/messages.js";
import type { PromptContext } from "../bot/context.js";
import { topicMessageOptions, topicReply } from "../bot/topic.js";
import { sendTextChunks } from "../shared/telegram-text.js";

const CODEXBOT_FINAL_INSTRUCTION =
  "Be concise; include outcome, validation, blockers if relevant; no extra explanation unless asked.";

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
  store: TopicStore;
  getConversationOptions: () => ConversationOptions;
  onNotInTopic: (ctx: PromptContext) => Promise<void>;
  requestApprovalFromTelegram: (ctx: PromptContext, request: ApprovalRequest) => Promise<ApprovalDecision>;
  requestUserInputFromTelegram?: (
    ctx: PromptContext,
    request: UserInputRequest
  ) => Promise<UserInputAnswers>;
};

export function createPromptRunner(deps: PromptRunnerDeps) {
  const topicTurnLocks = new Map<string, Promise<unknown>>();

  async function runPromptThroughCodex(
    ctx: PromptContext,
    topicBindingKey: string,
    text: string
  ): Promise<void> {
    if ((ctx.message.message_thread_id ?? 0) <= 0) {
      await deps.onNotInTopic(ctx);
      return;
    }

    const chatId = String(ctx.chat.id);
    const topicId = ctx.message.message_thread_id!;
    const finalOutputRelay = createFinalOutputRelay(
      (message) => ctx.api.sendMessage(ctx.chat.id, message, topicMessageOptions(ctx)),
      (path) => ctx.api.sendPhoto(ctx.chat.id, new InputFile(path), topicMessageOptions(ctx))
    );
    const runtimeOptions: PromptTurnRuntimeOptions = {
      approvalHandler: (request) => deps.requestApprovalFromTelegram(ctx, request),
      requestUserInputHandler: (request) =>
        deps.requestUserInputFromTelegram?.(ctx, request) ?? Promise.resolve({}),
    };

    try {
      await withTopicTurnLock(topicBindingKey, async () => {
        const binding = await deps.store.get(chatId, topicId);
        if (!binding) {
          const options = deps.getConversationOptions();
          const initialized = await createAndSendFirstMessageWithTimeoutContinuation(
            options,
            withCodexbotFinalInstruction(text),
            runtimeOptions
          );
          await deps.store.set(chatId, topicId, {
            threadId: initialized.threadId,
            title: "Codex session",
            cwd: options.cwd,
          });
          await finalizeTurn(initialized, finalOutputRelay);
          return;
        }

        try {
          const turn = await sendMessageWithTimeoutContinuation(
            binding.threadId,
            withCodexbotFinalInstruction(text),
            runtimeOptions
          );
          await finalizeTurn(turn, finalOutputRelay);
          return;
        } catch (error) {
          if (!isNoRolloutFoundError(error)) {
            throw error;
          }
        }

        try {
          const firstTurn = await sendMessageWithoutResumeWithTimeoutContinuation(
            binding.threadId,
            withCodexbotFinalInstruction(text),
            runtimeOptions
          );
          await finalizeTurn(firstTurn, finalOutputRelay);
        } catch {
          await recoverFromUnavailableThread(chatId, topicId, text, runtimeOptions, finalOutputRelay, binding);
        }
      });
    } catch (error) {
      await topicReply(
        ctx,
        formatFailure("Codex error.", error instanceof Error ? error.message : String(error))
      );
    }
  }

  async function withTopicTurnLock<T>(key: string, work: () => Promise<T>): Promise<T> {
    const previous = topicTurnLocks.get(key) ?? Promise.resolve();
    const current = previous.then(work);
    const safeCurrent = current.catch(() => undefined);
    topicTurnLocks.set(key, safeCurrent);

    try {
      return await current;
    } finally {
      if (topicTurnLocks.get(key) === safeCurrent) {
        topicTurnLocks.delete(key);
      }
    }
  }

  async function finalizeTurn(
    turn: TimedTurnLike | { status: "completed"; threadId: string; response: string; imagePaths?: string[] } |
      { status: "timed_out"; threadId: string; completion: Promise<TurnCompletion> },
    finalOutputRelay: FinalOutputRelay
  ): Promise<void> {
    const completion = turn.status === "completed"
      ? completionFromCompletedTurn(turn)
      : await turn.completion;
    await finalOutputRelay.send(completion);
  }

  async function recoverFromUnavailableThread(
    chatId: string,
    topicId: number,
    text: string,
    runtimeOptions: PromptTurnRuntimeOptions,
    finalOutputRelay: FinalOutputRelay,
    binding: { title: string; cwd: string }
  ): Promise<void> {
    const defaults = deps.getConversationOptions();
    const options = { ...defaults, cwd: binding.cwd || defaults.cwd };
    const initialized = await createAndSendFirstMessageWithTimeoutContinuation(
      options,
      withCodexbotFinalInstruction(text),
      runtimeOptions
    );
    await deps.store.set(chatId, topicId, {
      threadId: initialized.threadId,
      title: binding.title,
      cwd: options.cwd,
    });
    await finalizeTurn(initialized, finalOutputRelay);
  }

  return {
    runPromptThroughCodex,
  };
}

function isNoRolloutFoundError(error: unknown): boolean {
  return error instanceof Error && error.message.includes("no rollout found for thread id");
}

function withCodexbotFinalInstruction(text: string): string {
  return text + "\n\n" + CODEXBOT_FINAL_INSTRUCTION;
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

  return {
    async send(completion: TurnCompletion): Promise<void> {
      const output = completion.response?.trim() ? completion.response : EMPTY_CODEX_RESPONSE;
      await queueMessage(output);
      for (const path of completion.imagePaths ?? []) {
        try {
          await imageSender(path);
        } catch {
          await queueMessage("Image generated but Telegram upload failed:\n" + path);
        }
      }
    },
  };
}
