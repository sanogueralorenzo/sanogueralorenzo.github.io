import process from "node:process";
import { Bot } from "grammy";
import { TopicStore } from "./adapters/topic-store.js";
import {
  clearThreadGoal,
  getThreadGoal,
  setThreadGoalObjective,
  setThreadGoalStatus,
} from "./adapters/app-server/client.js";
import { closeSharedAppServer } from "./adapters/app-server/connection.js";
import { registerBotHandlers } from "./bot/index.js";
import { createApprovalService } from "./bot/approvals.js";
import type { PromptContext } from "./bot/context.js";
import { quickActionsKeyboard } from "./bot/keyboards.js";
import { HELP_TEXT, formatFailure } from "./bot/messages.js";
import { withActionErrorBoundary, withChatLock } from "./bot/middleware.js";
import { topicKeyFromContext, topicMessageOptions, topicReply } from "./bot/topic.js";
import { getConversationOptionsFromEnv, loadRuntimeConfig } from "./config.js";
import { createGoalActions } from "./services/goal-actions.js";
import { createPromptRunner } from "./services/prompt-runner.js";
import { createTopicActions, topicActionFailure } from "./services/topic-actions.js";
import { createUserInputService } from "./services/user-input.js";
import { createVoiceService } from "./services/voice.js";

const runtimeConfig = loadRuntimeConfig();
const {
  token,
  topicFile,
  defaultApprovalDecision,
  allowedChatIds,
  userHome,
} = runtimeConfig;

const store = new TopicStore(topicFile);
const bot = new Bot(token);
const APPROVAL_REQUEST_TIMEOUT_MS = 10 * 60 * 1000;
const TYPING_KEEPALIVE_INTERVAL_MS = 4000;

const topicActions = createTopicActions({ store });
const goalActions = createGoalActions({
  store,
  getGoal: getThreadGoal,
  setGoalObjective: setThreadGoalObjective,
  setGoalStatus: setThreadGoalStatus,
  clearGoal: clearThreadGoal,
});
const approvalService = createApprovalService({
  defaultApprovalDecision,
  timeoutMs: APPROVAL_REQUEST_TIMEOUT_MS,
});
const userInputService = createUserInputService();
const promptRunner = createPromptRunner({
  store,
  getConversationOptions: () => getConversationOptionsFromEnv(userHome),
  onNotInTopic: async (ctx) => {
    await topicReply(ctx, "Send prompts inside a Telegram Topic. Use /new [title] to create one.", {
      reply_markup: quickActionsKeyboard(),
    });
  },
  requestApprovalFromTelegram: approvalService.requestApprovalFromTelegram,
  requestUserInputFromTelegram: (ctx, request) =>
    userInputService.requestUserInputFromTelegram(ctx, request),
});
const voiceService = createVoiceService({
  token,
  projectRoot: process.cwd(),
});

registerBotHandlers(bot, {
  isChatAllowed: (chatId) => allowedChatIds.has(chatId),
  onStart: sendStartResponse,
  onHelp: sendHelpResponse,
  onAction: async (ctx, action) => {
    await withTopicActionLock(ctx, async () => {
      if (action === "new") {
        await topicActions.createTopic(ctx, "");
      } else {
        await topicActions.archiveTopic(ctx);
      }
    });
  },
  onNew: async (ctx, title) => {
    await withTopicActionLock(ctx, () => topicActions.createTopic(ctx, title));
  },
  onArchive: async (ctx) => {
    await withTopicActionLock(ctx, () => topicActions.archiveTopic(ctx));
  },
  onRename: async (ctx, title) => {
    await withTopicActionLock(ctx, () => topicActions.renameTopic(ctx, title));
  },
  onGoal: async (ctx, text) => {
    await withTopicActionLock(ctx, () =>
      goalActions.executeGoalCommand(
        String(ctx.chat.id),
        ctx.message.message_thread_id ?? 0,
        text,
        (message, options) => topicReply(ctx, message, options)
      )
    );
  },
  onTryApprovalText: (ctx, text) => approvalService.resolveApprovalFromText(ctx, text),
  onTryUserInputText: (ctx, text) => userInputService.resolveUserInputFromText(ctx, text),
  onPrompt: async (ctx, text) => {
    await withChatLock(topicKeyFromContext(ctx), async () => {
      await withTelegramTypingKeepAlive(ctx, () =>
        promptRunner.runPromptThroughCodex(ctx, topicKeyFromContext(ctx), text)
      );
    });
  },
  onVoice: async (ctx) => {
    await withChatLock(topicKeyFromContext(ctx), async () => {
      await withTelegramTypingKeepAlive(ctx, async () => {
        try {
          const transcript = await voiceService.transcribeVoiceMessage(ctx);
          await promptRunner.runPromptThroughCodex(ctx, topicKeyFromContext(ctx), transcript);
        } catch (error) {
          await topicReply(
            ctx,
            formatFailure("Voice transcription failed.", error instanceof Error ? error.message : String(error))
          );
        }
      });
    });
  },
});

bot.catch(async (error) => {
  console.error("Telegram bot error:", error.error);
});

let shuttingDown = false;
for (const signal of ["SIGINT", "SIGTERM"] as const) {
  process.once(signal, () => {
    if (shuttingDown) {
      return;
    }
    shuttingDown = true;
    void (async () => {
      console.log("Received " + signal + "; shutting down gracefully.");
      bot.stop();
      await closeSharedAppServer();
      process.exit(0);
    })();
  });
}

console.log("Telegram Codex bridge is running.");
console.log(
  "Telegram chat allowlist is active (" +
    allowedChatIds.size +
    " chat id" +
    (allowedChatIds.size === 1 ? "" : "s") +
    ")."
);
await runBotLoop();

async function withTopicActionLock(ctx: PromptContext, work: () => Promise<void>): Promise<void> {
  await withActionErrorBoundary(
    () => withChatLock(topicKeyFromContext(ctx), work),
    (message) => topicReply(ctx, topicActionFailure("Topic action failed.", new Error(message)))
  );
}

async function sendHelpResponse(ctx: PromptContext): Promise<void> {
  await topicReply(ctx, HELP_TEXT, { reply_markup: quickActionsKeyboard() });
}

async function sendStartResponse(ctx: PromptContext): Promise<void> {
  await sendHelpResponse(ctx);
}

async function withTelegramTypingKeepAlive<T>(
  ctx: PromptContext,
  run: () => Promise<T>
): Promise<T> {
  const sendTyping = async () => {
    try {
      await ctx.api.sendChatAction(ctx.chat.id, "typing", topicMessageOptions(ctx));
    } catch {
      // Ignore transient chat-action failures; request flow should continue.
    }
  };

  await sendTyping();
  const interval = setInterval(() => {
    void sendTyping();
  }, TYPING_KEEPALIVE_INTERVAL_MS);

  try {
    return await run();
  } finally {
    clearInterval(interval);
  }
}

async function runBotLoop(): Promise<never> {
  while (true) {
    try {
      const me = await bot.api.getMe();
      console.log("Telegram auth OK: @" + (me.username ?? me.first_name));
      await bot.start({
        drop_pending_updates: true,
        onStart: (info) => {
          console.log("Telegram polling started as @" + (info.username ?? info.first_name));
        },
      });
      console.error("Telegram polling stopped unexpectedly; retrying in 2s.");
    } catch (error) {
      const message = error instanceof Error ? error.stack ?? error.message : String(error);
      console.error("Telegram bot loop error: " + message);
    }

    await delay(2000);
  }
}

function delay(milliseconds: number): Promise<void> {
  return new Promise((resolve) => {
    setTimeout(resolve, milliseconds);
  });
}
