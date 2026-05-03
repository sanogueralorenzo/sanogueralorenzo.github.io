import { Bot } from "grammy";
import { ActionName } from "../shared/actions.js";
import { PromptContext, ReplyFn } from "./context.js";
import { registerCommandHandlers } from "./commands.js";
import { registerMessageHandlers } from "./messages-handler.js";

type BotHandlers = {
  isChatAllowed?: (chatId: string) => boolean;
  onStart: (chatId: string, reply: ReplyFn) => Promise<void>;
  onHelp: (chatId: string, reply: ReplyFn) => Promise<void>;
  onAction: (chatId: string, action: ActionName, reply: ReplyFn) => Promise<void>;
  onTryResumeText: (chatId: string, text: string, reply: ReplyFn) => Promise<boolean>;
  onTryNewFolderText: (chatId: string, text: string, reply: ReplyFn) => Promise<boolean>;
  onTryApprovalText: (ctx: PromptContext, chatId: string, text: string) => Promise<boolean>;
  onPrompt: (ctx: PromptContext, chatId: string, text: string) => Promise<void>;
  onVoice: (ctx: PromptContext, chatId: string) => Promise<void>;
};

export function registerBotHandlers(bot: Bot, handlers: BotHandlers): void {
  bot.use(async (ctx, next) => {
    if (!handlers.isChatAllowed) {
      await next();
      return;
    }

    const chatId = ctx.chat?.id;
    if (chatId === undefined || chatId === null) {
      await next();
      return;
    }

    if (!handlers.isChatAllowed(String(chatId))) {
      return;
    }

    await next();
  });

  registerCommandHandlers(bot, {
    onStart: handlers.onStart,
    onHelp: handlers.onHelp,
    onNew: (chatId, reply) => handlers.onAction(chatId, "new", reply),
    onResume: (chatId, reply) => handlers.onAction(chatId, "resume", reply),
    onDelete: (chatId, reply) => handlers.onAction(chatId, "delete", reply),
  });

  registerMessageHandlers(bot, {
    onStart: handlers.onStart,
    onHelp: handlers.onHelp,
    onAction: handlers.onAction,
    onTryResumeText: handlers.onTryResumeText,
    onTryNewFolderText: handlers.onTryNewFolderText,
    onTryApprovalText: handlers.onTryApprovalText,
    onPrompt: handlers.onPrompt,
    onVoice: handlers.onVoice
  });
}
