import { execFile } from "node:child_process";
import { mkdir, readFile, readdir, realpath, stat, writeFile } from "node:fs/promises";
import { homedir, tmpdir } from "node:os";
import { basename, dirname, isAbsolute, relative, resolve, sep } from "node:path";
import { promisify } from "node:util";
import type OpenAI from "openai";
import { containsSecret, isSensitivePath } from "./security.js";
import type { Store } from "../conversation/store.js";

const run = promisify(execFile);
const MAX_OUTPUT = 30_000;
const string = { type: "string" } as const;

export interface ToolContext {
  cwd: string | null;
  sessionId: string;
  memoryScope: string;
  signal?: AbortSignal;
}

export interface ToolResult {
  output: string;
  summary: string;
}

export interface AgentTool {
  definition: OpenAI.Responses.FunctionTool;
  execute(args: Record<string, unknown>, context: ToolContext): Promise<ToolResult>;
}

function tool(
  name: string,
  description: string,
  properties: Record<string, unknown>,
  execute: AgentTool["execute"],
): AgentTool {
  return {
    definition: {
      type: "function",
      name,
      description,
      strict: true,
      parameters: { type: "object", properties, required: Object.keys(properties), additionalProperties: false },
    },
    execute,
  };
}

function text(args: Record<string, unknown>, key: string): string {
  const value = args[key];
  if (typeof value !== "string" || !value) throw new Error(`Expected non-empty string: ${key}`);
  return value;
}

function clipped(value: string): string {
  return value.length <= MAX_OUTPUT ? value : `${value.slice(0, MAX_OUTPUT)}\n… output clipped by Agent`;
}

function assertInside(root: string, target: string): void {
  const path = relative(root, target);
  if (path === ".." || path.startsWith(`..${sep}`) || isAbsolute(path)) throw new Error("Path is outside the active project.");
}

async function projectPath(root: string | null, requested: string, create = false): Promise<string> {
  if (!root) throw new Error("This session has no active project directory.");
  if (isSensitivePath(requested)) throw new Error("Agent will not access credential or secret files.");
  const project = await realpath(root);
  const target = resolve(project, requested);
  assertInside(project, target);
  if (!create) {
    const canonical = await realpath(target);
    assertInside(project, canonical);
    return canonical;
  }
  let parent = project;
  for (const part of relative(project, dirname(target)).split(sep).filter(Boolean)) {
    const child = resolve(parent, part);
    try {
      parent = await realpath(child);
      assertInside(project, parent);
      if (!(await stat(parent)).isDirectory()) throw new Error("A parent path is not a directory.");
    } catch (error) {
      if ((error as NodeJS.ErrnoException).code !== "ENOENT") throw error;
      await mkdir(child);
      parent = child;
    }
  }
  const destination = resolve(parent, basename(target));
  try {
    const existing = await realpath(destination);
    assertInside(project, existing);
    return existing;
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code !== "ENOENT") throw error;
    return destination;
  }
}

function sandbox(program: string, args: string[], project: string): { executable: string; args: string[] } {
  if (process.platform !== "darwin") return { executable: program, args };
  const quote = (value: string) => value.replaceAll("\\", "\\\\").replaceAll('"', '\\"');
  const readable = [project, ...(process.env.PATH ?? "").split(":").filter(Boolean)]
    .map((path) => `(subpath "${quote(path)}")`).join(" ");
  const temporary = tmpdir();
  const writable = [project, temporary, temporary.startsWith("/var/") ? `/private${temporary}` : temporary];
  const profile = [
    "(version 1)", "(deny default)", "(allow process*)", '(deny process-exec (literal "/usr/bin/security"))',
    "(allow sysctl*)", "(allow mach*)", "(allow ipc*)", "(allow file-read-metadata)",
    `(allow file-read* (require-any ${readable} (require-not (subpath "${quote(homedir())}"))))`,
    ...writable.map((path) => `(allow file-write* (subpath "${quote(path)}"))`),
    "(deny network*)",
  ].join(" ");
  return { executable: "/usr/bin/sandbox-exec", args: ["-p", profile, program, ...args] };
}

function refuses(program: string, args: string[]): boolean {
  return (program === "node" && args.some((value) => value === "-e" || value === "--eval"))
    || (program === "python3" && args.includes("-c"))
    || (program === "find" && args.some((value) => ["-exec", "-execdir", "-delete"].includes(value)))
    || (program === "npm" && args.some((value) => value === "exec" || value === "x"))
    || (program === "git" && args.some((value) => ["clean", "reset", "push"].includes(value)));
}

export function createTools(store: Store, options: { allowCodeTools: boolean; allowCodeWrites?: boolean; allowMemoryWrite?: boolean }): AgentTool[] {
  const tools = [tool("memory_search", "Search durable personal or project memory.", { query: string }, async (args, context) => {
    const found = store.searchMemories(context.memoryScope, text(args, "query"));
    return { output: found.map((item) => `- ${item.content}`).join("\n") || "No matching memory.", summary: `${found.length} memories` };
  })];

  if (options.allowMemoryWrite !== false) tools.push(tool("remember", "Save one durable, non-secret fact or preference.", { fact: string }, async (args, context) => {
    const fact = text(args, "fact").trim();
    if (/\b(api[_ -]?key|password|secret|token)\b/i.test(fact) || containsSecret(fact)) throw new Error("Agent will not store suspected secrets in memory.");
    store.remember(context.memoryScope, fact, context.sessionId);
    return { output: "Saved.", summary: "memory saved" };
  }));

  if (options.allowCodeTools) tools.push(
    tool("read_file", "Read a UTF-8 project file.", { path: string }, async (args, context) => {
      const path = await projectPath(context.cwd, text(args, "path"));
      return { output: clipped(await readFile(path, "utf8")), summary: `read ${relative(context.cwd!, path)}` };
    }),
    tool("list_files", "List files in a project directory.", { path: string }, async (args, context) => {
      const entries = await readdir(await projectPath(context.cwd, text(args, "path")), { withFileTypes: true });
      return {
        output: entries.slice(0, 500).map((entry) => `${entry.isDirectory() ? "d" : "f"} ${entry.name}`).join("\n"),
        summary: `${entries.length} entries`,
      };
    }),
    tool("search_files", "Search project text with ripgrep.", { query: string, path: string }, async (args, context) => {
      const path = await projectPath(context.cwd, text(args, "path"));
      try {
        const { stdout } = await run("rg", ["-n", "--hidden", "--glob", "!.git", "--glob", "!.env*", "--glob", "!**/.env*", "--glob", "!**/*.{pem,p12,key}", "--", text(args, "query"), path], {
          cwd: context.cwd!, timeout: 15_000, maxBuffer: MAX_OUTPUT * 2, signal: context.signal,
        });
        return { output: clipped(stdout), summary: "search complete" };
      } catch (error) {
        const result = error as { code?: number; stderr?: string };
        if (result.code === 1) return { output: "No matches.", summary: "no matches" };
        throw new Error(clipped(result.stderr || String(error)));
      }
    }),
  );

  if (options.allowCodeTools && options.allowCodeWrites !== false) tools.push(
    tool("write_file", "Create or replace a UTF-8 project file.", { path: string, content: string }, async (args, context) => {
      const path = await projectPath(context.cwd, text(args, "path"), true);
      await writeFile(path, text(args, "content"), "utf8");
      return { output: "Written.", summary: `wrote ${relative(context.cwd!, path)}` };
    }),
    tool("replace_in_file", "Replace one exact text occurrence in a project file.", { path: string, oldText: string, newText: string }, async (args, context) => {
      const path = await projectPath(context.cwd, text(args, "path"));
      const oldText = text(args, "oldText");
      const content = await readFile(path, "utf8");
      const matches = content.split(oldText).length - 1;
      if (matches !== 1) throw new Error(`Expected exactly one match, found ${matches}.`);
      await writeFile(path, content.replace(oldText, String(args.newText ?? "")), "utf8");
      return { output: "Replaced.", summary: `edited ${relative(context.cwd!, path)}` };
    }),
    tool("run_command", "Run one non-interactive development command without a shell.", {
      program: { type: "string", enum: ["npm", "pnpm", "yarn", "node", "python3", "git", "rg", "find", "ls", "pwd", "swift", "swiftc", "xcodebuild", "gradle", "./gradlew", "pytest", "cargo", "go", "make"] },
      args: { type: "array", items: string },
    }, async (args, context) => {
      if (!context.cwd) throw new Error("This session has no active project directory.");
      const program = text(args, "program");
      const commandArgs = args.args;
      if (!Array.isArray(commandArgs) || !commandArgs.every((value) => typeof value === "string")) throw new Error("Expected a string array: args");
      if (commandArgs.some((value) => isAbsolute(value) || value === ".." || value.startsWith(`..${sep}`) || value.includes(`${sep}..${sep}`))) {
        throw new Error("Command arguments must stay inside the active project.");
      }
      if (refuses(program, commandArgs)) {
        throw new Error("Agent refused a destructive or unbounded command.");
      }
      const environment = Object.fromEntries(Object.entries(process.env).filter(([key]) => !/(?:KEY|TOKEN|SECRET|PASSWORD|CREDENTIAL)/i.test(key)));
      const executable = program === "./gradlew" ? await projectPath(context.cwd, program) : program;
      const command = sandbox(executable, commandArgs, await realpath(context.cwd));
      try {
        const { stdout, stderr } = await run(command.executable, command.args, {
          cwd: context.cwd, timeout: 120_000, maxBuffer: MAX_OUTPUT * 2, signal: context.signal, env: environment,
        });
        return { output: clipped([stdout, stderr].filter(Boolean).join("\n")) || "Command completed with no output.", summary: `${program} complete` };
      } catch (error) {
        const result = error as { code?: number; stdout?: string; stderr?: string };
        return {
          output: clipped(`Exit ${result.code ?? "failed"}\n${result.stdout ?? ""}\n${result.stderr ?? String(error)}`),
          summary: `command failed (${result.code ?? "error"})`,
        };
      }
    }),
  );

  return tools;
}

export function executeTool(tools: AgentTool[], name: string, rawArguments: string, context: ToolContext): Promise<ToolResult> {
  const selected = tools.find((candidate) => candidate.definition.name === name);
  if (!selected) throw new Error(`Unknown tool: ${name}`);
  try {
    return selected.execute(JSON.parse(rawArguments) as Record<string, unknown>, context);
  } catch {
    throw new Error(`Invalid JSON arguments for ${name}.`);
  }
}
