import { spawn } from "node:child_process";
import { mkdtemp, readFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import type { CodexEventType, CodexInfo, CodexSession } from "./types.js";

export type CodexEmit = (type: CodexEventType, data: Record<string, unknown>, raw?: Record<string, unknown>) => void;

export class CodexCli {
  constructor(private readonly bin: string) {}

  async info(): Promise<CodexInfo> {
    const capabilities = {
      transport: "sse" as const,
      sessions: true as const,
      cancellation: true as const,
      rawEvents: true as const,
    };
    return new Promise((resolve) => {
      const child = spawn(this.bin, ["--version"], { stdio: ["ignore", "pipe", "pipe"] });
      let stdout = "";
      let stderr = "";
      child.stdout.on("data", (chunk: Buffer) => (stdout += chunk.toString()));
      child.stderr.on("data", (chunk: Buffer) => (stderr += chunk.toString()));
      child.on("error", (error) => resolve({ available: false, error: error.message, capabilities }));
      child.on("close", (code) => {
        resolve({
          available: code === 0,
          path: this.bin,
          ...(code === 0 ? { version: stdout.trim() } : { error: stderr.trim() || stdout.trim() || `Exited ${code}` }),
          capabilities,
        });
      });
    });
  }

  async runTurn(signal: AbortSignal, session: CodexSession, text: string, emit: CodexEmit): Promise<CodexRunResult> {
    const tempDir = await mkdtemp(join(tmpdir(), "codex-web-"));
    const lastMessagePath = join(tempDir, "last-message.txt");
    const args = ["exec"];
    if (session.codexThreadId) args.push("resume");
    args.push("--json", "--output-last-message", lastMessagePath, "--cd", session.cwd);
    if (session.codexThreadId) args.push(session.codexThreadId);
    args.push("-");

    return new Promise((resolve, reject) => {
      const child = spawn(this.bin, args, { stdio: ["pipe", "pipe", "pipe"], signal });
      let stderr = "";
      let buffer = "";
      let codexThreadId: string | null = null;

      child.stdin.end(text);
      child.stderr.on("data", (chunk: Buffer) => (stderr += chunk.toString()));
      child.stdout.on("data", (chunk: Buffer) => {
        buffer += chunk.toString();
        const lines = buffer.split(/\r?\n/);
        buffer = lines.pop() ?? "";
        for (const line of lines) {
          if (line.trim()) {
            const mapped = mapCodexLine(line);
            if (mapped.threadId) codexThreadId = mapped.threadId;
            emit(mapped.type, mapped.data, mapped.raw);
          }
        }
      });
      child.on("error", (error) => reject(error));
      child.on("close", async (code) => {
        try {
          if (signal.aborted) {
            reject(new CancelledError("Turn cancelled."));
            return;
          }
          if (code !== 0) {
            reject(new Error(stderr.trim() || `Codex exited with status ${code}.`));
            return;
          }
          const finalAnswer = await readFile(lastMessagePath, "utf8").catch(() => "");
          resolve({ finalAnswer: finalAnswer.trim(), codexThreadId });
        } finally {
          await rm(tempDir, { recursive: true, force: true });
        }
      });
    });
  }
}

export type CodexRunResult = {
  finalAnswer: string;
  codexThreadId: string | null;
};

export class CancelledError extends Error {}

export function mapCodexLine(line: string): {
  type: CodexEventType;
  data: Record<string, unknown>;
  raw: Record<string, unknown>;
  threadId: string | null;
} {
  try {
    const raw = JSON.parse(line) as Record<string, unknown>;
    const label = String(raw.type ?? raw.event ?? raw.method ?? "").toLowerCase();
    const text = findString(raw, ["delta", "text", "message", "summary", "output"]);
    const threadId = findString(raw, ["thread_id", "threadId", "session_id", "sessionId", "conversation_id"]);
    if (label.includes("assistant") || label.includes("agent") || label.includes("message")) {
      return { type: "assistant.output", data: { text, label }, raw, threadId };
    }
    if (label.includes("tool") || label.includes("command") || label.includes("exec")) {
      return { type: "tool.output", data: { text, label }, raw, threadId };
    }
    return { type: "codex.event", data: { label }, raw, threadId };
  } catch (error) {
    return {
      type: "codex.event",
      data: { line, error: (error as Error).message },
      raw: { line },
      threadId: null,
    };
  }
}

function findString(value: unknown, keys: string[]): string | null {
  if (!value || typeof value !== "object") return null;
  const record = value as Record<string, unknown>;
  for (const key of keys) {
    const candidate = record[key];
    if (typeof candidate === "string" && candidate.trim()) return candidate;
  }
  for (const candidate of Object.values(record)) {
    const found = findString(candidate, keys);
    if (found) return found;
  }
  return null;
}
