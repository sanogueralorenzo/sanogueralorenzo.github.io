import { execFile } from "node:child_process";
import { mkdir, readFile, readdir, realpath, stat, writeFile } from "node:fs/promises";
import { basename, dirname, isAbsolute, relative, resolve, sep } from "node:path";
import { homedir, tmpdir } from "node:os";
import { promisify } from "node:util";
import type OpenAI from "openai";
import { containsSecret, isSensitivePath } from "./security.js";
import type { Store } from "./store.js";

const execFileAsync = promisify(execFile);
const MAX_OUTPUT = 30_000;

export interface ToolContext {
  cwd: string | null;
  sessionId: string;
  memoryScope: string;
  signal?: AbortSignal;
  delegate?: (task: string) => Promise<string>;
}

export interface ToolResult {
  output: string;
  summary: string;
}

export interface A1RTool {
  definition: OpenAI.Responses.FunctionTool;
  execute(args: Record<string, unknown>, context: ToolContext): Promise<ToolResult>;
}

function requireString(args: Record<string, unknown>, key: string): string {
  const value = args[key];
  if (typeof value !== "string" || value.length === 0) throw new Error(`Expected non-empty string: ${key}`);
  return value;
}

async function scopedPath(root: string | null, requested: string, mayCreate = false): Promise<string> {
  if (!root) throw new Error("This session has no active project directory.");
  if (isSensitivePath(requested)) throw new Error("A1R will not access credential or secret files.");
  const canonicalRoot = await realpath(root);
  const target = resolve(canonicalRoot, requested);
  let canonical: string;
  if (mayCreate) {
    try {
      canonical = await realpath(target);
    } catch {
      canonical = resolve(await realpath(dirname(target)), basename(target));
    }
  } else {
    canonical = await realpath(target);
  }
  const rel = relative(canonicalRoot, canonical);
  if (rel.startsWith(`..${sep}`) || rel === ".." || isAbsolute(rel)) {
    throw new Error("Path is outside the active project.");
  }
  return canonical;
}

function clipped(value: string): string {
  if (value.length <= MAX_OUTPUT) return value;
  return `${value.slice(0, MAX_OUTPUT)}\n… output clipped by A1R`;
}

function sandboxedCommand(program: string, args: string[], projectRoot: string): { executable: string; args: string[] } {
  if (process.platform !== "darwin") return { executable: program, args };
  const quote = (value: string) => value.replaceAll("\\", "\\\\").replaceAll('"', '\\"');
  const pathDirectories = (process.env.PATH ?? "").split(":").filter(Boolean);
  const readableRules = [projectRoot, ...pathDirectories]
    .map((path) => `(subpath "${quote(path)}")`)
    .join(" ");
  const temporary = tmpdir();
  const writable = [projectRoot, temporary, temporary.startsWith("/var/") ? `/private${temporary}` : temporary];
  const profile = [
    "(version 1)",
    "(deny default)",
    "(allow process*)",
    '(deny process-exec (literal "/usr/bin/security"))',
    "(allow sysctl*)",
    "(allow mach*)",
    "(allow ipc*)",
    "(allow file-read-metadata)",
    `(allow file-read* (require-any ${readableRules} (require-not (subpath "${quote(homedir())}"))))`,
    ...writable.map((path) => `(allow file-write* (subpath "${quote(path)}"))`),
    "(deny network*)",
  ].join(" ");
  return { executable: "/usr/bin/sandbox-exec", args: ["-p", profile, program, ...args] };
}

async function prepareWritePath(root: string | null, requested: string): Promise<string> {
  if (!root) throw new Error("This session has no active project directory.");
  if (isSensitivePath(requested)) throw new Error("A1R will not access credential or secret files.");
  const canonicalRoot = await realpath(root);
  const lexicalTarget = resolve(canonicalRoot, requested);
  const lexicalRelative = relative(canonicalRoot, lexicalTarget);
  if (lexicalRelative.startsWith(`..${sep}`) || lexicalRelative === ".." || isAbsolute(lexicalRelative)) {
    throw new Error("Path is outside the active project.");
  }
  const parts = lexicalRelative.split(sep);
  let current = canonicalRoot;
  for (const part of parts.slice(0, -1)) {
    const candidate = resolve(current, part);
    try {
      const canonical = await realpath(candidate);
      const rel = relative(canonicalRoot, canonical);
      if (rel.startsWith(`..${sep}`) || rel === ".." || isAbsolute(rel)) throw new Error("Path is outside the active project.");
      if (!(await stat(canonical)).isDirectory()) throw new Error("A parent path is not a directory.");
      current = canonical;
    } catch (error) {
      if ((error as NodeJS.ErrnoException).code !== "ENOENT") throw error;
      await mkdir(candidate);
      current = candidate;
    }
  }
  return scopedPath(canonicalRoot, requested, true);
}

export function createTools(store: Store, options: { allowCodeTools: boolean; allowDelegation: boolean }): A1RTool[] {
  const tools: A1RTool[] = [
    {
      definition: {
        type: "function",
        name: "memory_search",
        description: "Search durable personal or project memory when earlier context may matter.",
        strict: true,
        parameters: {
          type: "object",
          properties: { query: { type: "string" } },
          required: ["query"],
          additionalProperties: false,
        },
      },
      async execute(args, context) {
        const found = store.searchMemories(context.memoryScope, requireString(args, "query"));
        return { output: found.map((item) => `- ${item.content}`).join("\n") || "No matching memory.", summary: `${found.length} memories` };
      },
    },
    {
      definition: {
        type: "function",
        name: "remember",
        description: "Save one durable, non-secret fact or preference for future conversations.",
        strict: true,
        parameters: {
          type: "object",
          properties: { fact: { type: "string" } },
          required: ["fact"],
          additionalProperties: false,
        },
      },
      async execute(args, context) {
        const fact = requireString(args, "fact").trim();
        if (/\b(api[_ -]?key|password|secret|token)\b/i.test(fact) || containsSecret(fact)) throw new Error("A1R will not store suspected secrets in memory.");
        store.remember(context.memoryScope, fact, context.sessionId);
        return { output: "Saved.", summary: "memory saved" };
      },
    },
  ];

  if (options.allowCodeTools) {
    tools.push(
      {
        definition: {
          type: "function", name: "read_file", description: "Read a UTF-8 text file inside the active project.", strict: true,
          parameters: { type: "object", properties: { path: { type: "string" } }, required: ["path"], additionalProperties: false },
        },
        async execute(args, context) {
          const path = await scopedPath(context.cwd, requireString(args, "path"));
          const content = clipped(await readFile(path, "utf8"));
          return { output: content, summary: `read ${relative(context.cwd!, path)}` };
        },
      },
      {
        definition: {
          type: "function", name: "list_files", description: "List files in a project directory. Use a relative path.", strict: true,
          parameters: { type: "object", properties: { path: { type: "string" } }, required: ["path"], additionalProperties: false },
        },
        async execute(args, context) {
          const path = await scopedPath(context.cwd, requireString(args, "path"));
          const entries = await readdir(path, { withFileTypes: true });
          return {
            output: entries.slice(0, 500).map((entry) => `${entry.isDirectory() ? "d" : "f"} ${entry.name}`).join("\n"),
            summary: `${entries.length} entries`,
          };
        },
      },
      {
        definition: {
          type: "function", name: "search_files", description: "Search project text with ripgrep.", strict: true,
          parameters: {
            type: "object",
            properties: { query: { type: "string" }, path: { type: "string" } },
            required: ["query", "path"], additionalProperties: false,
          },
        },
        async execute(args, context) {
          const path = await scopedPath(context.cwd, requireString(args, "path"));
          try {
            const { stdout } = await execFileAsync("rg", ["-n", "--hidden", "--glob", "!.git", "--glob", "!.env*", "--glob", "!**/.env*", "--glob", "!**/*.{pem,p12,key}", "--", requireString(args, "query"), path], {
              cwd: context.cwd!, timeout: 15_000, maxBuffer: MAX_OUTPUT * 2, signal: context.signal,
            });
            return { output: clipped(stdout), summary: "search complete" };
          } catch (error) {
            const result = error as { code?: number; stdout?: string; stderr?: string };
            if (result.code === 1) return { output: "No matches.", summary: "no matches" };
            throw new Error(clipped(result.stderr || String(error)));
          }
        },
      },
      {
        definition: {
          type: "function", name: "write_file", description: "Create or replace a UTF-8 text file inside the active project.", strict: true,
          parameters: {
            type: "object",
            properties: { path: { type: "string" }, content: { type: "string" } },
            required: ["path", "content"], additionalProperties: false,
          },
        },
        async execute(args, context) {
          const requested = requireString(args, "path");
          const root = context.cwd;
          if (!root) throw new Error("This session has no active project directory.");
          const path = await prepareWritePath(root, requested);
          await writeFile(path, requireString(args, "content"), "utf8");
          return { output: "Written.", summary: `wrote ${relative(root, path)}` };
        },
      },
      {
        definition: {
          type: "function", name: "replace_in_file", description: "Replace one exact text occurrence inside a project file.", strict: true,
          parameters: {
            type: "object",
            properties: { path: { type: "string" }, oldText: { type: "string" }, newText: { type: "string" } },
            required: ["path", "oldText", "newText"], additionalProperties: false,
          },
        },
        async execute(args, context) {
          const path = await scopedPath(context.cwd, requireString(args, "path"));
          const oldText = requireString(args, "oldText");
          const content = await readFile(path, "utf8");
          const occurrences = content.split(oldText).length - 1;
          if (occurrences !== 1) throw new Error(`Expected exactly one match, found ${occurrences}.`);
          await writeFile(path, content.replace(oldText, String(args.newText ?? "")), "utf8");
          return { output: "Replaced.", summary: `edited ${relative(context.cwd!, path)}` };
        },
      },
      {
        definition: {
          type: "function", name: "run_command", description: "Run one non-interactive development command in the active project without a shell.", strict: true,
          parameters: {
            type: "object",
            properties: {
              program: { type: "string", enum: ["npm", "pnpm", "yarn", "node", "python3", "git", "rg", "find", "ls", "pwd", "swift", "swiftc", "xcodebuild", "gradle", "./gradlew", "pytest", "cargo", "go", "make"] },
              args: { type: "array", items: { type: "string" } },
            },
            required: ["program", "args"], additionalProperties: false,
          },
        },
        async execute(args, context) {
          if (!context.cwd) throw new Error("This session has no active project directory.");
          const program = requireString(args, "program");
          const commandArgs = args.args;
          if (!Array.isArray(commandArgs) || !commandArgs.every((argument) => typeof argument === "string")) {
            throw new Error("Expected a string array: args");
          }
          if (commandArgs.some((argument) => isAbsolute(argument) || argument === ".." || argument.startsWith(`..${sep}`) || argument.includes(`${sep}..${sep}`))) {
            throw new Error("Command arguments must stay inside the active project.");
          }
          if ((program === "node" && commandArgs.some((argument) => argument === "-e" || argument === "--eval"))
            || (program === "python3" && commandArgs.includes("-c"))
            || (program === "find" && commandArgs.some((argument) => argument === "-exec" || argument === "-execdir" || argument === "-delete"))
            || (program === "npm" && commandArgs.some((argument) => argument === "exec" || argument === "x"))
            || (program === "git" && commandArgs.some((argument) => ["clean", "reset", "push"].includes(argument)))) {
            throw new Error("A1R refused a destructive or unbounded command.");
          }
          try {
            const environment = Object.fromEntries(Object.entries(process.env).filter(([key]) => !/(?:KEY|TOKEN|SECRET|PASSWORD|CREDENTIAL)/i.test(key)));
            const executable = program === "./gradlew" ? await scopedPath(context.cwd, program) : program;
            const command = sandboxedCommand(executable, commandArgs, await realpath(context.cwd));
            const { stdout, stderr } = await execFileAsync(command.executable, command.args, {
              cwd: context.cwd, timeout: 120_000, maxBuffer: MAX_OUTPUT * 2, signal: context.signal, env: environment,
            });
            const output = clipped([stdout, stderr].filter(Boolean).join("\n")) || "Command completed with no output.";
            return { output, summary: `${program} complete` };
          } catch (error) {
            const result = error as { code?: number; stdout?: string; stderr?: string };
            return {
              output: clipped(`Exit ${result.code ?? "failed"}\n${result.stdout ?? ""}\n${result.stderr ?? String(error)}`),
              summary: `command failed (${result.code ?? "error"})`,
            };
          }
        },
      },
    );
  }

  if (options.allowDelegation) {
    tools.push({
      definition: {
        type: "function", name: "delegate_task", description: "Delegate one independent read-only investigation and return its concise findings.", strict: true,
        parameters: { type: "object", properties: { task: { type: "string" } }, required: ["task"], additionalProperties: false },
      },
      async execute(args, context) {
        if (!context.delegate) throw new Error("Delegation is unavailable.");
        const output = await context.delegate(requireString(args, "task"));
        return { output, summary: "delegated investigation complete" };
      },
    });
  }

  return tools;
}

export async function executeTool(
  tools: A1RTool[],
  name: string,
  rawArguments: string,
  context: ToolContext,
): Promise<ToolResult> {
  const tool = tools.find((candidate) => candidate.definition.name === name);
  if (!tool) throw new Error(`Unknown tool: ${name}`);
  let args: Record<string, unknown>;
  try {
    args = JSON.parse(rawArguments) as Record<string, unknown>;
  } catch {
    throw new Error(`Invalid JSON arguments for ${name}.`);
  }
  return tool.execute(args, context);
}
