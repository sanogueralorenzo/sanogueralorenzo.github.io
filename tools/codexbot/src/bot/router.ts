import { ActionName } from "../shared/actions.js";

export const START_COMMAND_ALIASES = ["start"] as const;
export const HELP_COMMAND_ALIASES = ["help", "h"] as const;
export const NEW_COMMAND_ALIASES = ["new", "n"] as const;
export const ARCHIVE_COMMAND_ALIASES = ["archive", "a"] as const;
export const RENAME_COMMAND_ALIASES = ["rename"] as const;
export const GOAL_COMMAND_ALIASES = ["goal"] as const;

const ACTION_BY_TEXT: Record<string, ActionName | "help" | "start"> = {
  new: "new",
  n: "new",
  "new topic": "new",
  archive: "archive",
  a: "archive",
  "archive topic": "archive",
  start: "start",
  help: "help",
  h: "help",
};

export function mapTextAction(input: string): ActionName | "help" | "start" | null {
  return ACTION_BY_TEXT[input] ?? null;
}
