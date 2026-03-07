import { execFile } from "node:child_process";
import { homedir } from "node:os";
import { join } from "node:path";
import { promisify } from "node:util";
import { expandHomePath } from "../shared/path-utils.js";

const execFileAsync = promisify(execFile);
const CODEX_SESSIONS_BIN = process.env.CODEX_SESSIONS_BIN?.trim() || "codex-sessions";

type DeleteResponse = {
  deleted: boolean;
  id: string;
  file_path: string;
};

type MessageResponse = {
  id: string;
  message: string | null;
};

export function resolveCodexHomeFromEnv(value: string | undefined): string {
  if (value && value.trim()) {
    return expandHomePath(value.trim());
  }
  return join(homedir(), ".codex");
}

export async function loadDesktopThreadTitles(codexHome: string): Promise<Map<string, string>> {
  try {
    const rows = await runCodexSessionsJson<Record<string, string>>([
      "titles",
      "--json",
      "--home",
      codexHome,
    ]);
    const titleByThreadId = new Map<string, string>();
    for (const [id, title] of Object.entries(rows)) {
      if (typeof id !== "string") {
        continue;
      }
      if (typeof title !== "string") {
        continue;
      }
      const trimmed = title.trim();
      if (!trimmed) {
        continue;
      }
      titleByThreadId.set(id, trimmed);
    }
    return titleByThreadId;
  } catch {
    return new Map();
  }
}

export async function deleteSessionByThreadId(
  threadId: string,
  codexHome: string
): Promise<{ deleted: boolean; filePath: string | null; from: "sessions" | null }> {
  try {
    const result = await runCodexSessionsJson<DeleteResponse>([
      "delete",
      threadId,
      "--json",
      "--home",
      codexHome,
    ]);

    return {
      deleted: Boolean(result.deleted),
      filePath: typeof result.file_path === "string" ? result.file_path : null,
      from: "sessions",
    };
  } catch (error) {
    if (isNotFoundError(error)) {
      return { deleted: false, filePath: null, from: null };
    }
    throw error;
  }
}

export async function loadLatestAssistantMessageByThreadId(
  threadId: string,
  codexHome: string
): Promise<string | null> {
  try {
    const result = await runCodexSessionsJson<MessageResponse>([
      "message",
      threadId,
      "--json",
      "--home",
      codexHome,
    ]);

    if (typeof result.message === "string" && result.message.trim()) {
      return result.message;
    }
    return null;
  } catch (error) {
    if (isNotFoundError(error)) {
      return null;
    }
    return null;
  }
}

async function runCodexSessionsJson<T>(args: string[]): Promise<T> {
  const stdout = await runCodexSessions(args);
  try {
    return JSON.parse(stdout) as T;
  } catch (error) {
    throw new Error(`Invalid JSON from ${CODEX_SESSIONS_BIN}: ${(error as Error).message}`);
  }
}

async function runCodexSessions(args: string[]): Promise<string> {
  try {
    const { stdout } = await execFileAsync(CODEX_SESSIONS_BIN, args, {
      maxBuffer: 10 * 1024 * 1024,
    });
    return stdout;
  } catch (error) {
    const err = error as NodeJS.ErrnoException & { stderr?: string };
    if (err.code === "ENOENT") {
      throw new Error(
        `Missing '${CODEX_SESSIONS_BIN}' CLI. Install codex-sessions before running codex-remote.`
      );
    }
    throw error;
  }
}

function isNotFoundError(error: unknown): boolean {
  const err = error as { stderr?: string; message?: string } | null;
  const text = `${err?.stderr ?? ""}\n${err?.message ?? ""}`.toLowerCase();
  return text.includes("no session matches id or prefix");
}
