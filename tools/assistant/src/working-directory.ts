import { realpathSync, statSync } from "node:fs";
import { homedir } from "node:os";
import { join, resolve } from "node:path";
import { AgentDoc, configure, defineTool, hook, ToolTask } from "@earendil-works/pi-durable";
import { Type } from "typebox";
import { HomeDoc } from "./state.ts";

export function resolveWorkingDirectory(path: string, cwd: string): string {
  const input = path.trim();
  if (!input) throw new Error("Choose an existing directory");
  const expanded = input === "~" ? homedir() : input.startsWith("~/") ? join(homedir(), input.slice(2)) : input;
  const directory = realpathSync(resolve(cwd, expanded));
  if (!statSync(directory).isDirectory()) throw new Error("Choose a directory, not a file");
  return directory;
}

// Pi persists the normalized arguments before execution, so relative changes replay against the same target.
export const workingDirectoryHook = hook(ToolTask, { beforeTool: async (call, api, context) => {
  if (call.name !== "working_directory" || typeof call.arguments.path !== "string") return;
  const cwd = (await api.snapshot(AgentDoc, api.conversationId, context))?.cwd || process.cwd();
  return { arguments: { path: resolveWorkingDirectory(call.arguments.path, cwd) } };
} });

export const workingDirectory = defineTool({ name: "working_directory", replay: "safe", executionMode: "sequential",
  description: "Read or change this conversation's working directory. Omit path to read it. Supply an existing absolute path, a path relative to the current directory, or ~/path to change it. Subsequent tools and new workers use that directory and its project instructions; existing workers keep their own directory. Coordinate ongoing work before switching.",
  parameters: Type.Object({ path: Type.Optional(Type.String({ minLength: 1 })) }, { additionalProperties: false }),
  execute: async (args, api, context) => {
    const current = (await api.agent(context)).cwd || process.cwd();
    const cwd = args.path === undefined ? current : resolveWorkingDirectory(args.path, current);
    if (args.path !== undefined) await api.commit(async tx => {
      await configure(tx, api.conversationId, { cwd });
      const session = (await tx.doc(HomeDoc)).sessions.find(session => session.conversationId === api.conversationId);
      if (session) session.cwd = cwd;
    }, context);
    return { output: [{ type: "text", text: JSON.stringify({ cwd }) }], details: { cwd } };
  } });
