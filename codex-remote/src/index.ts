import process from "node:process";
import { Bot, InputFile } from "grammy";
import { BindingStore } from "./adapters/binding-store.js";
import { registerBotHandlers } from "./bot/index.js";
import { createApprovalService } from "./bot/approvals.js";
import { PromptContext, ReplyFn, ReplyPhotoFn } from "./bot/context.js";
import { quickActionsKeyboard } from "./bot/keyboards.js";
import { HELP_TEXT, formatFailure } from "./bot/messages.js";
import { withActionErrorBoundary, withChatLock } from "./bot/middleware.js";
import { getConversationOptionsFromEnv, loadRuntimeConfig } from "./config.js";
import { createPromptRunner } from "./services/prompt-runner.js";
import { ListedFolderChoice, ListedThread, createThreadActions } from "./services/thread-actions.js";
import { createVoiceService } from "./services/voice.js";

const runtimeConfig = loadRuntimeConfig();
const {
  token,
  bindingFile,
  startImagePath,
  codexHome,
  defaultApprovalDecision,
  allowedChatIds,
  userHome
} = runtimeConfig;

const store = new BindingStore(bindingFile);
const bot = new Bot(token);

const pendingNewSessionChats = new Set<string>();
const pendingNewSessionCwds = new Map<string, string>();
const selectionStateByChat = new Map<
  string,
  { sessions: ListedThread[]; mode: "resume" | "delete"; folderChoices: ListedFolderChoice[] }
>();

const DEFAULT_THREADS_LIMIT = 25;
const APPROVAL_REQUEST_TIMEOUT_MS = 10 * 60 * 1000;
const TYPING_KEEPALIVE_INTERVAL_MS = 4000;

const threadActions = createThreadActions({
  codexHome,
  defaultThreadsLimit: DEFAULT_THREADS_LIMIT,
  store,
  pendingNewSessionChats,
  pendingNewSessionCwds,
  selectionStateByChat,
  resolveDefaultCwd: () => getConversationOptionsFromEnv(userHome).cwd,
  bindChatToThread
});

const approvalService = createApprovalService({
  defaultApprovalDecision,
  timeoutMs: APPROVAL_REQUEST_TIMEOUT_MS
});

const promptRunner = createPromptRunner({
  store,
  pendingNewSessionChats,
  getPendingNewSessionCwd: (chatId) => pendingNewSessionCwds.get(chatId) ?? null,
  clearPendingNewSessionCwd: (chatId) => {
    pendingNewSessionCwds.delete(chatId);
  },
  onThreadNotBound: async (ctx) => {
    await ctx.reply(HELP_TEXT, { reply_markup: quickActionsKeyboard() });
  },
  getConversationOptions: () => getConversationOptionsFromEnv(userHome),
  bindChatToThread,
  requestApprovalFromTelegram: approvalService.requestApprovalFromTelegram
});

const voiceService = createVoiceService({
  token,
  projectRoot: process.cwd()
});

registerBotHandlers(bot, {
  isChatAllowed: (chatId) => {
    if (!allowedChatIds) {
      return true;
    }
    return allowedChatIds.has(chatId);
  },
  onStart: async (_, reply, replyPhoto) => {
    await sendStartResponse(reply, replyPhoto);
  },
  onHelp: async (_, reply) => {
    await sendHelpResponse(reply);
  },
  onAction: async (chatId, action, reply) => {
    await withActionErrorBoundary(
      () =>
        withChatLock(chatId, async () => {
          await threadActions.executeAction(chatId, action, reply);
        }),
      (message) => reply(formatFailure("Action failed.", message))
    );
  },
  onTryResumeText: async (chatId, text, reply) => {
    return withChatLock(chatId, async () => threadActions.tryPickThreadByText(chatId, text, reply));
  },
  onTryNewFolderText: async (chatId, text, reply) => {
    return withChatLock(chatId, async () => threadActions.tryPickFolderChoiceByText(chatId, text, reply));
  },
  onTryApprovalText: async (ctx, chatId, text) => {
    return approvalService.resolveApprovalFromText(ctx, chatId, text);
  },
  onPrompt: async (ctx, chatId, text) => {
    await withChatLock(chatId, async () => {
      await withTelegramTypingKeepAlive(ctx as PromptContext, async () => {
        await promptRunner.runPromptThroughCodex(ctx as PromptContext, chatId, text);
      });
    });
  },
  onVoice: async (ctx, chatId) => {
    await withChatLock(chatId, async () => {
      await withTelegramTypingKeepAlive(ctx as PromptContext, async () => {
        try {
          const transcript = await voiceService.transcribeVoiceMessage(ctx as PromptContext);
          await promptRunner.runPromptThroughCodex(ctx as PromptContext, chatId, transcript);
        } catch (error) {
          const message = error instanceof Error ? error.message : String(error);
          await ctx.reply(formatFailure("Voice transcription failed.", message));
        }
      });
    });
  },
});

bot.catch(async (error) => {
  console.error("Telegram bot error:", error.error);
});

console.log(`Telegram Codex bridge is running. Codex home: ${codexHome}.`);
if (allowedChatIds) {
  console.log(`Telegram chat allowlist is active (${allowedChatIds.size} chat id${allowedChatIds.size === 1 ? "" : "s"}).`);
}
await runBotLoop();

async function runBotLoop(): Promise<never> {
  while (true) {
    try {
      const me = await bot.api.getMe();
      console.log(`Telegram auth OK: @${me.username ?? me.first_name}`);
      await bot.start({
        drop_pending_updates: true,
        onStart: (info) => {
          console.log(`Telegram polling started as @${info.username ?? info.first_name}`);
        }
      });
      console.error("Telegram polling stopped unexpectedly; retrying in 2s.");
    } catch (error) {
      const message = error instanceof Error ? error.stack ?? error.message : String(error);
      console.error(`Telegram bot loop error: ${message}`);
    }

    await delay(2000);
  }
}

function delay(milliseconds: number): Promise<void> {
  return new Promise((resolve) => {
    setTimeout(resolve, milliseconds);
  });
}

async function withTelegramTypingKeepAlive<T>(
  ctx: PromptContext,
  run: () => Promise<T>
): Promise<T> {
  const sendTyping = async () => {
    try {
      await ctx.api.sendChatAction(ctx.chat.id, "typing");
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

async function bindChatToThread(chatId: string, threadId: string): Promise<void> {
  await store.set(chatId, threadId);
}

async function sendHelpResponse(reply: ReplyFn): Promise<void> {
  await reply(HELP_TEXT, { reply_markup: quickActionsKeyboard() });
}

async function sendStartResponse(reply: ReplyFn, replyPhoto: ReplyPhotoFn): Promise<void> {
  await replyPhoto(new InputFile(startImagePath));
  await sendHelpResponse(reply);
}
