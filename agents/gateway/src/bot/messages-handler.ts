import { Bot } from "grammy";
import { ActionName } from "../shared/actions.js";
import { PromptContext } from "./context.js";
import { mapTextAction } from "./router.js";
import { ReplyFn } from "./context.js";

type MessageHandlers = {
  onHelp: (chatId: string, reply: ReplyFn) => Promise<void>;
  onAction: (chatId: string, action: ActionName, reply: ReplyFn) => Promise<void>;
  onTryResumeText: (chatId: string, text: string, reply: ReplyFn) => Promise<boolean>;
  onTryNewFolderText: (chatId: string, text: string, reply: ReplyFn) => Promise<boolean>;
  onTryApprovalText: (ctx: PromptContext, chatId: string, text: string) => Promise<boolean>;
  onPrompt: (ctx: PromptContext, chatId: string, text: string) => Promise<void>;
  onVoice: (ctx: PromptContext, chatId: string) => Promise<void>;
};

export function registerMessageHandlers(bot: Bot, handlers: MessageHandlers): void {
  bot.on("message:text", async (ctx) => {
    const text = ctx.message.text.trim();
    if (!text) {
      return;
    }

    const chatId = String(ctx.chat.id);
    if (await handlers.onTryApprovalText(ctx as PromptContext, chatId, text)) {
      return;
    }
    if (await handlers.onTryResumeText(chatId, text, (replyText, options) => ctx.reply(replyText, options))) {
      return;
    }
    if (await handlers.onTryNewFolderText(chatId, text, (replyText, options) => ctx.reply(replyText, options))) {
      return;
    }

    const normalized = text.toLowerCase();
    const mappedAction = mapTextAction(normalized);
    if (mappedAction) {
      if (mappedAction === "help") {
        await handlers.onHelp(chatId, (replyText, options) => ctx.reply(replyText, options));
        return;
      }

      await handlers.onAction(chatId, mappedAction, (replyText, options) => ctx.reply(replyText, options));
      return;
    }

    if (text.startsWith("/")) {
      return;
    }

    await handlers.onPrompt(ctx as PromptContext, chatId, text);
  });

  bot.on("message:voice", async (ctx) => {
    const chatId = String(ctx.chat.id);
    await handlers.onVoice(ctx as PromptContext, chatId);
  });
}
