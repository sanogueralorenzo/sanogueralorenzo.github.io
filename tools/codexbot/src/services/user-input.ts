import { Keyboard } from "grammy";
import type { UserInputAnswers, UserInputRequest } from "../adapters/app-server/client.js";
import type { PromptContext } from "../bot/context.js";
import { limitTelegramText } from "./voice.js";
import { topicKeyFromContext, topicReply } from "../bot/topic.js";

const USER_INPUT_TIMEOUT_MS = 10 * 60 * 1000;
const CANCEL_LABEL = "Cancel";
const OTHER_LABEL = "Other";
const REMOVE_KEYBOARD = { remove_keyboard: true } as const;

type PendingUserInput = {
  chatId: string;
  topicId?: number;
  api: PromptContext["api"];
  request: UserInputRequest;
  answers: UserInputAnswers;
  questionIndex: number;
  acceptingOther: boolean;
  timeout: NodeJS.Timeout;
  resolve: (answers: UserInputAnswers) => void;
};

export function createUserInputService(timeoutMs = USER_INPUT_TIMEOUT_MS) {
  const pendingByTopic = new Map<string, PendingUserInput>();

  function requestUserInputFromTelegram(
    ctx: PromptContext,
    request: UserInputRequest
  ): Promise<UserInputAnswers> {
    if (request.questions.length === 0) {
      return Promise.resolve({});
    }

    const key = topicKeyFromContext(ctx);
    const existing = pendingByTopic.get(key);
    if (existing) {
      finish(existing, {});
    }

    return new Promise<UserInputAnswers>((resolve) => {
      const pending: PendingUserInput = {
        chatId: String(ctx.chat.id),
        topicId: ctx.message.message_thread_id,
        api: ctx.api,
        request,
        answers: {},
        questionIndex: 0,
        acceptingOther: false,
        timeout: setTimeout(() => {
          if (pendingByTopic.get(key) !== pending) {
            return;
          }
          finish(pending, pending.answers);
          void pending.api.sendMessage(
            Number(pending.chatId),
            "Input timed out. Continuing without the remaining answers.",
            {
              reply_markup: REMOVE_KEYBOARD,
              ...(pending.topicId === undefined ? {} : { message_thread_id: pending.topicId }),
            }
          );
        }, timeoutMs),
        resolve,
      };

      pendingByTopic.set(key, pending);
      void sendCurrentQuestion(pending).catch(() => {
        if (pendingByTopic.get(key) === pending) {
          finish(pending, {});
        }
      });
    });
  }

  async function resolveUserInputFromText(ctx: PromptContext, text: string): Promise<boolean> {
    const key = topicKeyFromContext(ctx);
    const pending = pendingByTopic.get(key);
    if (!pending) {
      return false;
    }

    const answer = text.trim();
    if (!answer) {
      return true;
    }

    if (answer.toLowerCase() === CANCEL_LABEL.toLowerCase()) {
      finish(pending, pending.answers);
      await clearKeyboard(ctx, "Input cancelled. Continuing without the remaining answers.");
      return true;
    }

    const question = pending.request.questions[pending.questionIndex];
    if (!question) {
      finish(pending, pending.answers);
      return true;
    }

    if (question.options && !pending.acceptingOther) {
      const selected = question.options.find((option) => option.label === answer);
      if (selected) {
        await acceptAnswer(ctx, pending, selected.label);
        return true;
      }

      if (question.isOther && answer === OTHER_LABEL) {
        pending.acceptingOther = true;
        await ctx.api.sendMessage(chatIdNumber(pending.chatId), "Type your answer in a new message.", {
          ...(pending.topicId === undefined ? {} : { message_thread_id: pending.topicId }),
        });
        return true;
      }

      await sendCurrentQuestion(pending, "Please choose one of the displayed options.");
      return true;
    }

    await acceptAnswer(ctx, pending, answer);
    return true;
  }

  function hasPendingUserInput(ctx: PromptContext): boolean {
    return pendingByTopic.has(topicKeyFromContext(ctx));
  }

  async function acceptAnswer(
    ctx: PromptContext,
    pending: PendingUserInput,
    answer: string
  ): Promise<void> {
    const question = pending.request.questions[pending.questionIndex];
    if (!question) {
      finish(pending, pending.answers);
      return;
    }

    pending.answers[question.id] = { answers: [answer] };
    pending.questionIndex += 1;
    pending.acceptingOther = false;

    if (pending.questionIndex >= pending.request.questions.length) {
      const answers = pending.answers;
      finish(pending, answers);
      await clearKeyboard(ctx, "Thanks — continuing.");
      return;
    }

    await sendCurrentQuestion(pending);
  }

  async function sendCurrentQuestion(pending: PendingUserInput, prefix?: string): Promise<void> {
    const question = pending.request.questions[pending.questionIndex];
    if (!question) {
      finish(pending, pending.answers);
      return;
    }

    const lines = [
      prefix,
      `Codex needs your input (${pending.questionIndex + 1}/${pending.request.questions.length})`,
      question.header ? `${question.header}: ${question.question}` : question.question,
    ].filter((line): line is string => Boolean(line));

    if (question.isSecret) {
      lines.push("This answer may contain sensitive information; avoid sharing anything you do not want sent to Codex.");
    }

    const options = buildQuestionKeyboard(question);
    await pending.api.sendMessage(chatIdNumber(pending.chatId), limitTelegramText(lines.join("\n\n")), {
      ...(pending.topicId === undefined ? {} : { message_thread_id: pending.topicId }),
      ...(options ? { reply_markup: options } : {}),
    });
  }

  function finish(pending: PendingUserInput, answers: UserInputAnswers): void {
    clearTimeout(pending.timeout);
    const key = pending.chatId + ":" + (pending.topicId ?? 0);
    if (pendingByTopic.get(key) === pending) {
      pendingByTopic.delete(key);
    }
    pending.resolve(answers);
  }

  return {
    requestUserInputFromTelegram,
    resolveUserInputFromText,
    hasPendingUserInput,
  };
}

function buildQuestionKeyboard(
  question: UserInputRequest["questions"][number]
): Keyboard | null {
  const keyboard = new Keyboard();
  if (question.options?.length) {
    for (const option of question.options) {
      keyboard.text(option.label).row();
    }
    if (question.isOther) {
      keyboard.text(OTHER_LABEL).row();
    }
  }
  keyboard.text(CANCEL_LABEL);
  return keyboard.resized().oneTime();
}

async function clearKeyboard(ctx: PromptContext, text: string): Promise<void> {
  await topicReply(ctx, text, { reply_markup: REMOVE_KEYBOARD });
}

function chatIdNumber(chatId: string): number {
  const parsed = Number(chatId);
  if (!Number.isSafeInteger(parsed)) {
    throw new Error("Invalid Telegram chat id.");
  }
  return parsed;
}
