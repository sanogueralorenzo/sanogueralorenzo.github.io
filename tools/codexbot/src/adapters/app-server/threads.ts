import {
  ConversationOptions,
  ThreadSummary,
  THREAD_LIST_SOURCE_KINDS,
} from "./types.js";
import type { AppServerConnection } from "./connection.js";
import type { JsonValue } from "./generated/serde_json/JsonValue.js";
import type { ThreadListParams } from "./generated/v2/ThreadListParams.js";
import type { ThreadStartParams } from "./generated/v2/ThreadStartParams.js";
import { withAppServer } from "./connection.js";
import { asArray, asObject, getNumber, getString } from "./json.js";

export type ThreadDeleteResult = {
  deleted: boolean;
  message: string | null;
};

export async function listThreads(limit: number): Promise<ThreadSummary[]> {
  return withAppServer(async (client) => {
    const pageSize = Math.max(1, Math.trunc(limit));
    const threads: ThreadSummary[] = [];
    let cursor: string | null = null;

    while (threads.length < pageSize) {
      const remaining = pageSize - threads.length;
      const result = await client.send("thread/list", buildThreadListParams(remaining, cursor));
      const page = parseThreadListPage(result);
      threads.push(...page.threads);
      if (!page.nextCursor || page.threads.length === 0) {
        break;
      }
      cursor = page.nextCursor;
    }

    return threads;
  });
}

export async function startThreadOnClient(
  client: Pick<AppServerConnection, "send">,
  options: ConversationOptions
): Promise<string> {
  const result = await client.send("thread/start", buildThreadStartParams(options));
  const thread = asObject(result).thread;
  const threadId = asObject(thread).id;
  if (typeof threadId !== "string" || !threadId) {
    throw new Error("app-server thread/start did not return a thread id");
  }
  return threadId;
}

export async function deleteThreadById(threadId: string): Promise<ThreadDeleteResult> {
  await withAppServer(async (client) => {
    await client.send("thread/delete", { threadId });
  });

  return { deleted: true, message: null };
}

export async function archiveThreadById(threadId: string): Promise<void> {
  await withAppServer(async (client) => {
    await client.send("thread/archive", { threadId });
  });
}

export async function setThreadNameById(threadId: string, name: string): Promise<void> {
  await withAppServer(async (client) => {
    await client.send("thread/name/set", { threadId, name });
  });
}

export async function loadLatestAssistantMessageByThreadId(threadId: string): Promise<string | null> {
  try {
    return await withAppServer(async (client) => {
      const result = await client.send("thread/read", { threadId, includeTurns: true });
      const turns = asArray(asObject(asObject(result).thread).turns);

      for (let turnIndex = turns.length - 1; turnIndex >= 0; turnIndex -= 1) {
        const items = asArray(asObject(turns[turnIndex]).items);
        for (let itemIndex = items.length - 1; itemIndex >= 0; itemIndex -= 1) {
          const item = asObject(items[itemIndex]);
          if (item.type !== "agentMessage") {
            continue;
          }
          const text = getString(item.text);
          if (text) {
            return text;
          }
        }
      }

      return null;
    });
  } catch {
    // Showing the latest message is useful but should not prevent resuming a thread.
    return null;
  }
}

function parseThreadListPage(result: unknown): { threads: ThreadSummary[]; nextCursor: string | null } {
  const data = asArray(asObject(result).data);
  const nextCursor = getString(asObject(result).nextCursor);
  const threads: ThreadSummary[] = [];

  for (const entry of data) {
    const thread = asObject(entry);
    const id = getString(thread.id);
    const cwd = getString(thread.cwd);
    const name = getString(thread.name);
    const preview = getString(thread.preview) ?? "";
    const createdAt = getNumber(thread.createdAt);
    const updatedAt = getNumber(thread.updatedAt);

    if (!id || !cwd || createdAt === null || updatedAt === null) {
      continue;
    }

    threads.push({
      id,
      cwd,
      name,
      preview,
      isPinned: thread.isPinned === true,
      createdAt,
      updatedAt,
      path: getString(thread.path),
      source: normalizeSource(thread.source),
    });
  }

  return { threads, nextCursor };
}

function buildThreadListParams(limit: number, cursor: string | null): ThreadListParams {
  return {
    limit: Math.max(1, Math.trunc(limit)),
    sortKey: "updated_at",
    sourceKinds: Array.from(THREAD_LIST_SOURCE_KINDS),
    cursor,
  };
}

function normalizeSource(source: unknown): string {
  if (typeof source === "string") {
    return source;
  }

  if (!source || typeof source !== "object" || Array.isArray(source)) {
    return "unknown";
  }

  const sourceObj = source as Record<string, unknown>;
  const [kind, value] = Object.entries(sourceObj)[0] ?? ["unknown", null];
  if (typeof value === "string") {
    return `${kind}:${value}`;
  }
  return kind;
}

function buildThreadStartParams(options: ConversationOptions): ThreadStartParams {
  const params: ThreadStartParams = {
    cwd: options.cwd,
    experimentalRawEvents: false,
  };

  if (options.model) {
    params.model = options.model;
  }
  if (options.approvalPolicy) {
    params.approvalPolicy = options.approvalPolicy;
  }
  if (options.sandboxMode) {
    params.sandbox = options.sandboxMode;
  }

  const config = buildConfigOverrides(options.networkAccessEnabled, options.skipGitRepoCheck);
  if (config) {
    params.config = config;
  }

  return params;
}

function buildConfigOverrides(
  networkAccessEnabled?: boolean | null,
  skipGitRepoCheck?: boolean | null
): Record<string, JsonValue> | null {
  const overrides: Record<string, JsonValue> = {};

  if (networkAccessEnabled !== null && networkAccessEnabled !== undefined) {
    overrides.sandbox_workspace_write = {
      network_access: networkAccessEnabled,
    };
  }

  if (skipGitRepoCheck !== null && skipGitRepoCheck !== undefined) {
    overrides.ignore_git_repo_check = skipGitRepoCheck;
  }

  return Object.keys(overrides).length ? overrides : null;
}
