import { Bot } from "grammy";
import { ActionName } from "../shared/actions.js";
import { PromptContext } from "./context.js";
import { mapTextAction } from "./router.js";

type MessageHandlers = {
  onStart: (ctx: PromptContext) => Promise<void>;
  onHelp: (ctx: PromptContext) => Promise<void>;
  onAction: (ctx: PromptContext, action: ActionName) => Promise<void>;
  onTryApprovalText: (ctx: PromptContext, text: string) => Promise<boolean>;
  onTryUserInputText: (ctx: PromptContext, text: string) => Promise<boolean>;
  onPrompt: (ctx: PromptContext, text: string) => Promise<void>;
  onVoice: (ctx: PromptContext) => Promise<void>;
};

export function registerMessageHandlers(bot: Bot, handlers: MessageHandlers): void {
  bot.on("message:text", async (ctx) => {
    const text = ctx.message.text.trim();
    if (!text) {
      return;
    }

    const promptContext = ctx as PromptContext;
    if (await handlers.onTryUserInputText(promptContext, text)) {
      return;
    }
    if (await handlers.onTryApprovalText(promptContext, text)) {
      return;
    }

    const normalized = text.toLowerCase();
    const mappedAction = mapTextAction(normalized);
    if (mappedAction) {
      switch (mappedAction) {
        case "start":
          await handlers.onStart(promptContext);
          return;
        case "help":
          await handlers.onHelp(promptContext);
          return;
        default:
          await handlers.onAction(promptContext, mappedAction);
      }
      return;
    }

    await handlers.onPrompt(promptContext, text);
  });

  bot.on("message:voice", async (ctx) => {
    await handlers.onVoice(ctx as PromptContext);
  });
}
