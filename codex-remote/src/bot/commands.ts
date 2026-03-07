import { Bot } from "grammy";
import { ReplyFn, ReplyPhotoFn } from "./context.js";
import {
  DELETE_COMMAND_ALIASES,
  HELP_COMMAND_ALIASES,
  NEW_COMMAND_ALIASES,
  RESUME_COMMAND_ALIASES,
  START_COMMAND_ALIASES
} from "./router.js";

type CommandHandlers = {
  onStart: (chatId: string, reply: ReplyFn, replyPhoto: ReplyPhotoFn) => Promise<void>;
  onHelp: (chatId: string, reply: ReplyFn) => Promise<void>;
  onNew: (chatId: string, reply: ReplyFn) => Promise<void>;
  onResume: (chatId: string, reply: ReplyFn) => Promise<void>;
  onDelete: (chatId: string, reply: ReplyFn) => Promise<void>;
};

export function registerCommandHandlers(bot: Bot, handlers: CommandHandlers): void {
  for (const command of START_COMMAND_ALIASES) {
    bot.command(command, (ctx) =>
      handlers.onStart(
        String(ctx.chat.id),
        (text, options) => ctx.reply(text, options),
        (photo, options) => ctx.replyWithPhoto(photo, options)
      )
    );
  }

  for (const command of HELP_COMMAND_ALIASES) {
    bot.command(command, (ctx) => handlers.onHelp(String(ctx.chat.id), (text, options) => ctx.reply(text, options)));
  }

  for (const command of NEW_COMMAND_ALIASES) {
    bot.command(command, (ctx) => handlers.onNew(String(ctx.chat.id), (text, options) => ctx.reply(text, options)));
  }

  for (const command of RESUME_COMMAND_ALIASES) {
    bot.command(command, (ctx) =>
      handlers.onResume(String(ctx.chat.id), (text, options) => ctx.reply(text, options))
    );
  }

  for (const command of DELETE_COMMAND_ALIASES) {
    bot.command(command, (ctx) =>
      handlers.onDelete(String(ctx.chat.id), (text, options) => ctx.reply(text, options))
    );
  }
}
