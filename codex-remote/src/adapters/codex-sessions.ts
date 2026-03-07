import { readdir, readFile, rmdir, rm, writeFile } from "node:fs/promises";
import { homedir } from "node:os";
import { basename, dirname, isAbsolute, join, relative } from "node:path";
import { expandHomePath } from "../shared/path-utils.js";

export function resolveCodexHomeFromEnv(value: string | undefined): string {
  if (value && value.trim()) {
    return expandHomePath(value.trim());
  }
  return join(homedir(), ".codex");
}

export async function loadDesktopThreadTitles(codexHome: string): Promise<Map<string, string>> {
  const filePath = join(codexHome, ".codex-global-state.json");
  let raw: string;

  try {
    raw = await readFile(filePath, "utf8");
  } catch {
    return new Map();
  }

  let parsed: unknown;
  try {
    parsed = JSON.parse(raw);
  } catch {
    return new Map();
  }

  const root = (parsed ?? {}) as Record<string, unknown>;
  const threadTitles = root["thread-titles"] as Record<string, unknown> | undefined;
  const titles = threadTitles?.titles as Record<string, unknown> | undefined;
  if (!titles || typeof titles !== "object") {
    return new Map();
  }

  const titleByThreadId = new Map<string, string>();
  for (const [threadId, title] of Object.entries(titles)) {
    if (typeof title !== "string") {
      continue;
    }
    const trimmed = title.trim();
    if (!trimmed) {
      continue;
    }
    titleByThreadId.set(threadId, trimmed);
  }

  return titleByThreadId;
}

export async function forceSessionSource(
  threadId: string,
  codexHome: string,
  source: "vscode" | "cli" | "appServer" = "vscode",
  originator = "Codex Desktop"
): Promise<boolean> {
  const sessionsRoot = join(codexHome, "sessions");
  const filePath = await findSessionFileByThreadId(sessionsRoot, threadId);
  if (!filePath) {
    return false;
  }

  let raw: string;
  try {
    raw = await readFile(filePath, "utf8");
  } catch {
    return false;
  }

  const lines = raw.split("\n");
  if (!lines.length || !lines[0].trim()) {
    return false;
  }

  let first: Record<string, unknown>;
  try {
    first = JSON.parse(lines[0]) as Record<string, unknown>;
  } catch {
    return false;
  }

  const payload = first.payload as Record<string, unknown> | undefined;
  if (!payload || typeof payload !== "object") {
    return false;
  }

  const currentSource = typeof payload.source === "string" ? payload.source : null;
  const currentOriginator = typeof payload.originator === "string" ? payload.originator : null;
  if (currentSource === source && currentOriginator === originator) {
    return true;
  }

  payload.source = source;
  payload.originator = originator;
  first.payload = payload;
  lines[0] = JSON.stringify(first);

  try {
    await writeFile(filePath, `${lines.join("\n")}`, "utf8");
    return true;
  } catch {
    return false;
  }
}

export async function deleteSessionByThreadId(
  threadId: string,
  codexHome: string
): Promise<{ deleted: boolean; filePath: string | null; from: "sessions" | null }> {
  const root = join(codexHome, "sessions");
  const filePath = await findSessionFileByThreadId(root, threadId);
  if (!filePath) {
    return { deleted: false, filePath: null, from: null };
  }

  try {
    await rm(filePath);
  } catch (error) {
    const code = (error as NodeJS.ErrnoException | undefined)?.code;
    if (code === "ENOENT") {
      return { deleted: false, filePath, from: "sessions" };
    }
    throw error;
  }

  await pruneEmptyParentDirs(dirname(filePath), root);
  return { deleted: true, filePath, from: "sessions" };
}

export async function loadLatestAssistantMessageByThreadId(
  threadId: string,
  codexHome: string
): Promise<string | null> {
  const sessionsRoot = join(codexHome, "sessions");
  const filePath = await findSessionFileByThreadId(sessionsRoot, threadId);
  if (!filePath) {
    return null;
  }

  let raw: string;
  try {
    raw = await readFile(filePath, "utf8");
  } catch {
    return null;
  }

  let latest: string | null = null;
  const lines = raw.split("\n");
  for (const line of lines) {
    const text = extractAssistantTextFromSessionLine(line);
    if (text) {
      latest = text;
    }
  }

  return latest;
}

async function findSessionFileByThreadId(dir: string, threadId: string): Promise<string | null> {
  let entries;
  try {
    entries = await readdir(dir, { withFileTypes: true });
  } catch {
    return null;
  }

  for (const entry of entries) {
    const fullPath = join(dir, entry.name);
    if (entry.isDirectory()) {
      const nested = await findSessionFileByThreadId(fullPath, threadId);
      if (nested) {
        return nested;
      }
      continue;
    }

    if (entry.isFile() && entry.name.endsWith(".jsonl")) {
      const idFromName = extractIdFromName(entry.name);
      if (idFromName === threadId) {
        return fullPath;
      }
    }
  }

  return null;
}

function extractIdFromName(fileName: string): string | null {
  const name = basename(fileName, ".jsonl");
  const match = name.match(/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i);
  if (!match) {
    return null;
  }
  return match[0];
}

function extractAssistantTextFromSessionLine(line: string): string | null {
  const trimmed = line.trim();
  if (!trimmed) {
    return null;
  }

  let parsed: unknown;
  try {
    parsed = JSON.parse(trimmed);
  } catch {
    return null;
  }

  const root = asObject(parsed);
  if (root.type !== "response_item") {
    return null;
  }

  const payload = asObject(root.payload);
  if (payload.type !== "message" || payload.role !== "assistant") {
    return null;
  }

  const content = rootArray(payload.content);
  const textParts: string[] = [];
  for (const item of content) {
    const contentItem = asObject(item);
    const text = contentItem.text;
    if (typeof text === "string" && text.trim()) {
      textParts.push(text.trim());
    }
  }

  if (!textParts.length) {
    return null;
  }

  return textParts.join("\n\n");
}

async function pruneEmptyParentDirs(startDir: string, sessionsRoot: string): Promise<void> {
  let current = startDir;

  while (isSameDirOrChild(sessionsRoot, current) && current !== sessionsRoot) {
    let entries: string[];
    try {
      entries = await readdir(current);
    } catch {
      return;
    }

    if (entries.length > 0) {
      return;
    }

    try {
      await rmdir(current);
    } catch {
      return;
    }

    current = dirname(current);
  }
}

function isSameDirOrChild(parentDir: string, targetDir: string): boolean {
  const rel = relative(parentDir, targetDir);
  return rel === "" || (!rel.startsWith("..") && !isAbsolute(rel));
}

function asObject(value: unknown): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    return {};
  }
  return value as Record<string, unknown>;
}

function rootArray(value: unknown): unknown[] {
  if (!Array.isArray(value)) {
    return [];
  }
  return value;
}
