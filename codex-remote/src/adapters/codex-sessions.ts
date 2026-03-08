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
  action?: string;
  error?: string | null;
};

type DeleteBatchResponse = {
  action: string;
  dry_run: boolean;
  hard: boolean;
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

export async function listSessionsForSelection(
  codexHome: string,
  limit: number
): Promise<ListedSession[]> {
  const result = await runCodexSessionsJson<ListResponse>([
    "list",
    "--json",
    "--all",
    "--folders",
    "--home",
    codexHome,
    "--limit",
    String(Math.max(1, Math.trunc(limit))),
  ]);

  return result.data
    .filter((session) => !session.archived)
    .map((session) => {
      const rawTitle = typeof session.title === "string" ? session.title.trim() : "";
      const rawFolder = typeof session.folder === "string" ? session.folder.trim() : "";
      const rawCwd = typeof session.cwd === "string" ? session.cwd.trim() : "";

      return {
        id: session.id,
        title: rawTitle || "Untitled thread",
        folder: rawFolder || "unknown",
        cwd: rawCwd || process.cwd(),
        lastUpdatedAt: typeof session.last_updated_at === "string" ? session.last_updated_at : "",
      };
    });
}

export async function deleteSessionByThreadId(
  threadId: string,
  codexHome: string
): Promise<{ deleted: boolean; filePath: string | null; from: "sessions" | null }> {
  try {
    const payload = await runCodexSessionsJson<DeleteResponse | DeleteBatchResponse>([
      "delete",
      threadId,
      "--json",
      "--home",
      codexHome,
    ]);

    const result = normalizeDeleteResponse(payload, threadId);
    if (!result) {
      return { deleted: false, filePath: null, from: null };
    }

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

function normalizeDeleteResponse(
  payload: DeleteResponse | DeleteBatchResponse,
  requestedId: string
): DeleteResponse | null {
  if (isDeleteBatchResponse(payload)) {
    const match = payload.sessions.find((session) => session.id === requestedId);
    if (match) {
      return match;
    }
    return payload.sessions[0] ?? null;
  }
  return payload;
}

function isDeleteBatchResponse(value: unknown): value is DeleteBatchResponse {
  if (!value || typeof value !== "object") {
    return false;
  }
  return Array.isArray((value as { sessions?: unknown }).sessions);
}
