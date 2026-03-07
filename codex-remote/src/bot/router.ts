import { ActionName } from "../shared/actions.js";

export const START_COMMAND_ALIASES = ["start"] as const;
export const HELP_COMMAND_ALIASES = ["help", "h"] as const;
export const NEW_COMMAND_ALIASES = ["new", "n"] as const;
export const RESUME_COMMAND_ALIASES = ["resume", "r"] as const;
export const DELETE_COMMAND_ALIASES = ["delete", "d"] as const;

export function mapTextAction(input: string): ActionName | "help" | "start" | null {
  if (input === "new" || input === "n" || input === "new chat") {
    return "new";
  }
  if (input === "resume" || input === "r" || input === "resume chat") {
    return "resume";
  }
  if (input === "delete" || input === "d" || input === "delete chat") {
    return "delete";
  }
  if (input === "start") {
    return "start";
  }
  if (input === "help" || input === "h") {
    return "help";
  }
  return null;
}
