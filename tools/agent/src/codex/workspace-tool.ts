import { realpathSync, statSync } from "node:fs";
import { homedir } from "node:os";
import { dirname, isAbsolute, sep } from "node:path";
import { isSensitivePath } from "../workspace/security.js";

export const OPEN_FOLDER_TOOL = {
  name: "open_folder",
  description: "When the user asks to open a local folder, repository, or project, find its absolute path and open it for this conversation. It becomes the working directory on the next turn; stop after opening it.",
  inputSchema: {
    type: "object",
    properties: { path: { type: "string", description: "Absolute path to the folder." } },
    required: ["path"],
    additionalProperties: false,
  },
};

function response(success: boolean, text: string) {
  return { success, contentItems: [{ type: "inputText", text }] };
}

export function openFolder(path: unknown, agentHome: string): { result: ReturnType<typeof response>; cwd?: string } {
  const input = typeof path === "string" ? path.replace(/^~(?=\/|$)/, homedir()) : "";
  if (!isAbsolute(input)) return { result: response(false, "Find the folder and pass its absolute path.") };
  try {
    const cwd = realpathSync(input);
    const home = realpathSync(homedir());
    const privateHome = realpathSync(agentHome);
    if (!statSync(cwd).isDirectory()) return { result: response(false, "That path is not a folder.") };
    if (dirname(cwd) === "/" || cwd === home || home.startsWith(`${cwd}${sep}`)
      || cwd === privateHome || cwd.startsWith(`${privateHome}${sep}`) || isSensitivePath(cwd)) {
      return { result: response(false, "Choose a specific, non-private folder.") };
    }
    return { result: response(true, `Opened ${cwd}. Continue the user's work in the next turn.`), cwd };
  } catch {
    return { result: response(false, "Folder not found or inaccessible.") };
  }
}
