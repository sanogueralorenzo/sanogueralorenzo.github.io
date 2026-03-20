import { execFile } from "node:child_process";
import { homedir } from "node:os";
import { basename, join } from "node:path";
import { promisify } from "node:util";
import { expandHomePath } from "../shared/path-utils.js";

const execFileAsync = promisify(execFile);
const CODEX_APP_SERVER_BIN = process.env.CODEX_APP_SERVER_BIN?.trim() || "codex-app-server";

type DeleteResponse = {
  id: string;
  file_path: string;
  status: "succeeded" | "skipped" | "failed";
  reason: "completed" | "dry_run" | "pinned" | "error";
  message?: string | null;
};

type DeleteBatchResponse = {
  operation: string;
  dry_run: boolean;
  processed: number;
  succeeded: number;
  failed: number;
  skipped: number;
  sessions: DeleteResponse[];
};

type MessageResponse = {
  id: string;
  message: string | null;
};

type ListResponse = {
  data: Array<{
    id: string;
    title: string | null;
    folder: string;
    cwd: string | null;
    archived: boolean;
    last_updated_at: string;
  }>;
};

export type ListedSession = {
  id: string;
  title: string;
  folder: string;
  cwd: string;
  lastUpdatedAt: string;
};

export function resolveCodexHomeFromEnv(value: string | undefined): string {
  if (value && value.trim()) {
    return expandHomePath(value.trim());
  }
  return join(homedir(), ".codex");
}

export async function listSessionsForSelection(
  codexHome: string,
  limit: number
): Promise<ListedSession[]> {
  const result = await runCodexAppServerSessionsJson<ListResponse>([
    "list",
    "--json",
    "--all",
    "--folders",
    "--home",
    codexHome,
    "--limit",
    String(Math.max(1, Math.trunc(limit))),
  ]);

  const sessions = result.data.filter((session) => !session.archived).map(toListedSession);
  return sortSessionsByLastUpdatedDesc(sessions);
}

export async function deleteSessionByThreadId(
  threadId: string,
  codexHome: string
): Promise<{
  deleted: boolean;
  filePath: string | null;
  from: "sessions" | null;
  status: DeleteResponse["status"] | null;
  reason: DeleteResponse["reason"] | null;
  message: string | null;
}> {
  const payload = await runCodexAppServerSessionsJsonOrNullOnNotFound<DeleteBatchResponse>([
    "delete",
    threadId,
    "--json",
    "--home",
    codexHome,
  ]);
  if (!payload) {
    return emptyDeleteResult();
  }

  const result = payload.sessions.find((session) => session.id === threadId) ?? payload.sessions[0] ?? null;
  if (!result) {
    return emptyDeleteResult();
  }

  return {
    deleted: result.status === "succeeded",
    filePath: typeof result.file_path === "string" ? result.file_path : null,
    from: "sessions",
    status: result.status,
    reason: result.reason,
    message: typeof result.message === "string" ? result.message : null
  };
}

export async function loadLatestAssistantMessageByThreadId(
  threadId: string,
  codexHome: string
): Promise<string | null> {
  const result = await runCodexAppServerSessionsJsonOrNullOnNotFound<MessageResponse>([
    "message",
    threadId,
    "--json",
    "--home",
    codexHome,
  ]);
  if (!result) {
    return null;
  }

  if (typeof result.message === "string" && result.message.trim()) {
    return result.message;
  }
  return null;
}

async function runCodexAppServerSessionsJson<T>(args: string[]): Promise<T> {
  const stdout = await runCodexAppServerSessions(args);
  try {
    return JSON.parse(stdout) as T;
  } catch (error) {
    throw new Error(`Invalid JSON from ${CODEX_APP_SERVER_BIN}: ${(error as Error).message}`);
  }
}

async function runCodexAppServerSessionsJsonOrNullOnNotFound<T>(args: string[]): Promise<T | null> {
  try {
    return await runCodexAppServerSessionsJson<T>(args);
  } catch (error) {
    if (isNotFoundError(error)) {
      return null;
    }
    throw error;
  }
}

async function runCodexAppServerSessions(args: string[]): Promise<string> {
  const commandArgs = ["sessions", ...args];
  try {
    const { stdout } = await execFileAsync(CODEX_APP_SERVER_BIN, commandArgs, {
      maxBuffer: 10 * 1024 * 1024,
    });
    return stdout;
  } catch (error) {
    const err = error as NodeJS.ErrnoException & { stderr?: string };
    if (err.code === "ENOENT") {
      throw new Error(
        `Missing '${CODEX_APP_SERVER_BIN}' CLI. Install codex-app-server before running codex-remote.`
      );
    }
    throw error;
  }
}

function toListedSession(session: ListResponse["data"][number]): ListedSession {
  const rawTitle = typeof session.title === "string" ? session.title.trim() : "";
  const rawFolder = typeof session.folder === "string" ? session.folder.trim() : "";
  const rawCwd = typeof session.cwd === "string" ? session.cwd.trim() : "";

  return {
    id: session.id,
    title: rawTitle,
    folder: rawFolder || (rawCwd ? basename(rawCwd) : ""),
    cwd: rawCwd || process.cwd(),
    lastUpdatedAt: typeof session.last_updated_at === "string" ? session.last_updated_at : "",
  };
}

export function sortSessionsByLastUpdatedDesc(sessions: ListedSession[]): ListedSession[] {
  return sessions
    .map((session, index) => ({
      session,
      index,
      updatedAtMs: toUpdatedAtEpochMs(session.lastUpdatedAt),
    }))
    .sort((a, b) => {
      if (b.updatedAtMs !== a.updatedAtMs) {
        return b.updatedAtMs - a.updatedAtMs;
      }
      return a.index - b.index;
    })
    .map((entry) => entry.session);
}

function emptyDeleteResult(): {
  deleted: boolean;
  filePath: null;
  from: null;
  status: null;
  reason: null;
  message: null;
} {
  return { deleted: false, filePath: null, from: null, status: null, reason: null, message: null };
}

function isNotFoundError(error: unknown): boolean {
  const err = error as { stderr?: string; message?: string } | null;
  const text = `${err?.stderr ?? ""}\n${err?.message ?? ""}`.toLowerCase();
  return text.includes("no session matches id or prefix");
}

function toUpdatedAtEpochMs(value: string): number {
  const parsed = Date.parse(value);
  return Number.isFinite(parsed) ? parsed : 0;
}
