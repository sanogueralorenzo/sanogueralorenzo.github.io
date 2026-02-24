import { ActionName } from "../shared/actions.js";

export const HELP_COMMAND_ALIASES = ["start", "help", "h"] as const;
export const NEW_COMMAND_ALIASES = ["new", "n"] as const;
export const RESUME_COMMAND_ALIASES = ["resume", "r"] as const;
export const DELETE_COMMAND_ALIASES = ["delete", "d"] as const;

export function mapTextAction(input: string): ActionName | "help" | null {
  if (input === "new" || input === "n" || input === "new chat") {
    return "new";
  }
  if (input === "resume" || input === "r" || input === "resume chat") {
    return "resume";
  }
  if (input === "delete" || input === "d" || input === "delete chat") {
    return "delete";
  }
  if (input === "help" || input === "h" || input === "start") {
    return "help";
  }
  return null;
}
