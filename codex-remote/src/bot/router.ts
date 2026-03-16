import { ActionName } from "../shared/actions.js";

export const START_COMMAND_ALIASES = ["start"] as const;
export const HELP_COMMAND_ALIASES = ["help", "h"] as const;
export const NEW_COMMAND_ALIASES = ["new", "n"] as const;
export const RESUME_COMMAND_ALIASES = ["resume", "r"] as const;
export const DELETE_COMMAND_ALIASES = ["delete", "d"] as const;
export const RESTART_COMMAND_ALIASES = ["restart"] as const;

const ACTION_BY_TEXT: Record<string, ActionName | "help" | "start" | "restart"> = {
  new: "new",
  n: "new",
  "new chat": "new",
  resume: "resume",
  r: "resume",
  "resume chat": "resume",
  delete: "delete",
  d: "delete",
  "delete chat": "delete",
  start: "start",
  help: "help",
  h: "help",
  restart: "restart"
};

export function mapTextAction(input: string): ActionName | "help" | "start" | "restart" | null {
  return ACTION_BY_TEXT[input] ?? null;
}
