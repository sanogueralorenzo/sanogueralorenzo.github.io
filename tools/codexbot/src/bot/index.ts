import { Bot } from "grammy";
import type { PromptContext } from "./context.js";
import type { ActionName } from "../shared/actions.js";
import { registerCommandHandlers } from "./commands.js";
import { registerMessageHandlers } from "./messages-handler.js";

type BotHandlers = {
  isChatAllowed?: (chatId: string) => boolean;
  onStart: (ctx: PromptContext) => Promise<void>;
  onHelp: (ctx: PromptContext) => Promise<void>;
  onAction: (ctx: PromptContext, action: ActionName) => Promise<void>;
  onNew: (ctx: PromptContext, title: string) => Promise<void>;
  onArchive: (ctx: PromptContext) => Promise<void>;
  onRename: (ctx: PromptContext, title: string) => Promise<void>;
  onGoal: (ctx: PromptContext, text: string) => Promise<void>;
  onTryApprovalText: (ctx: PromptContext, text: string) => Promise<boolean>;
  onTryUserInputText: (ctx: PromptContext, text: string) => Promise<boolean>;
  onPrompt: (ctx: PromptContext, text: string) => Promise<void>;
  onVoice: (ctx: PromptContext) => Promise<void>;
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
    onNew: handlers.onNew,
    onArchive: handlers.onArchive,
    onRename: handlers.onRename,
    onGoal: handlers.onGoal,
  });

  registerMessageHandlers(bot, {
    onStart: handlers.onStart,
    onHelp: handlers.onHelp,
    onAction: handlers.onAction,
    onTryApprovalText: handlers.onTryApprovalText,
    onTryUserInputText: handlers.onTryUserInputText,
    onPrompt: handlers.onPrompt,
    onVoice: handlers.onVoice
  });
}
