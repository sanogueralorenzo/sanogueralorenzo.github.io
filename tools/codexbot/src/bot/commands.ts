import { Bot } from "grammy";
import type { PromptContext } from "./context.js";
import {
  ARCHIVE_COMMAND_ALIASES,
  GOAL_COMMAND_ALIASES,
  HELP_COMMAND_ALIASES,
  NEW_COMMAND_ALIASES,
  RENAME_COMMAND_ALIASES,
  START_COMMAND_ALIASES
} from "./router.js";

type CommandHandlers = {
  onStart: (ctx: PromptContext) => Promise<void>;
  onHelp: (ctx: PromptContext) => Promise<void>;
  onNew: (ctx: PromptContext, title: string) => Promise<void>;
  onArchive: (ctx: PromptContext) => Promise<void>;
  onRename: (ctx: PromptContext, title: string) => Promise<void>;
  onGoal: (ctx: PromptContext, text: string) => Promise<void>;
};

export function registerCommandHandlers(bot: Bot, handlers: CommandHandlers): void {
  for (const command of START_COMMAND_ALIASES) {
    bot.command(command, (ctx) => handlers.onStart(ctx as PromptContext));
  }

  for (const command of HELP_COMMAND_ALIASES) {
    bot.command(command, (ctx) => handlers.onHelp(ctx as PromptContext));
  }

  for (const command of NEW_COMMAND_ALIASES) {
    bot.command(command, (ctx) =>
      handlers.onNew(ctx as PromptContext, parseCommandPayload(ctx.message?.text))
    );
  }

  for (const command of ARCHIVE_COMMAND_ALIASES) {
    bot.command(command, (ctx) => handlers.onArchive(ctx as PromptContext));
  }

  for (const command of RENAME_COMMAND_ALIASES) {
    bot.command(command, (ctx) =>
      handlers.onRename(ctx as PromptContext, parseCommandPayload(ctx.message?.text))
    );
  }

  for (const command of GOAL_COMMAND_ALIASES) {
    bot.command(command, (ctx) =>
      handlers.onGoal(ctx as PromptContext, parseCommandPayload(ctx.message?.text))
    );
  }
}

function parseCommandPayload(text: string | undefined): string {
  return text?.trim().replace(/^\/\S+\s*/, "").trim() ?? "";
}
