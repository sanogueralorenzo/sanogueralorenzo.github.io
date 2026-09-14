import { homedir } from "node:os";
import { join } from "node:path";

export function expandHomePath(input: string): string {
  const home = homedir();
  if (input === "~") {
    return home;
  }
  if (input.startsWith("~/")) {
    return join(home, input.slice(2));
  }
  if (input === "$HOME") {
    return home;
  }
  if (input.startsWith("$HOME/")) {
    return join(home, input.slice("$HOME/".length));
  }
  if (input === "${HOME}") {
    return home;
  }
  if (input.startsWith("${HOME}/")) {
    return join(home, input.slice("${HOME}/".length));
  }
  return input;
}
