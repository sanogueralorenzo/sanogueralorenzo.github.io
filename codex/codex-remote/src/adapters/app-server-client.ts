import {
  ConversationOptions,
  ThreadSummary,
  THREAD_LIST_SOURCE_KINDS,
  TimedCreateTurnResult,
  TimedTurnResult,
  TurnRuntimeOptions
} from "./app-server-client-types.js";
import { withAppServer, withTurnClient } from "./app-server-connection.js";
import { asArray, asObject, getNumber, getString } from "./app-server-json.js";
import { runTurnWithTimeout } from "./app-server-turn-runner.js";

export type {
  ApprovalDecision,
  ApprovalPolicy,
  ApprovalRequest,
  SandboxMode,
  ThreadSummary,
  TimedCreateTurnResult,
  TimedTurnResult,
  TurnProgressEvent,
} from "./app-server-client-types.js";

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

export async function sendMessageWithTimeoutContinuation(
  threadId: string,
  text: string,
  runtimeOptions?: TurnRuntimeOptions
): Promise<TimedTurnResult> {
  return sendMessageWithTimeoutContinuationInternal(threadId, text, true, runtimeOptions);
}

export async function sendMessageWithoutResumeWithTimeoutContinuation(
  threadId: string,
  text: string,
  runtimeOptions?: TurnRuntimeOptions
): Promise<TimedTurnResult> {
  return sendMessageWithTimeoutContinuationInternal(threadId, text, false, runtimeOptions);
}

async function sendMessageWithTimeoutContinuationInternal(
  threadId: string,
  text: string,
  resumeFirst: boolean,
  runtimeOptions?: TurnRuntimeOptions
): Promise<TimedTurnResult> {
  return withTurnClient(runtimeOptions, async (client, handOffCompletion) => {
    const timed = await runTurnWithTimeout(
      client,
      threadId,
      text,
      resumeFirst,
      runtimeOptions?.onTurnEvent
    );
    if (timed.status === "completed") {
      return timed;
    }

    return {
      status: "timed_out",
      completion: handOffCompletion(timed.completion)
    };
  });
}

export async function createAndSendFirstMessageWithTimeoutContinuation(
  options: ConversationOptions,
  text: string,
  runtimeOptions?: TurnRuntimeOptions
): Promise<TimedCreateTurnResult> {
  return withTurnClient(runtimeOptions, async (client, handOffCompletion) => {
    const threadId = await startThreadOnClient(client, options);
    const timed = await runTurnWithTimeout(
      client,
      threadId,
      text,
      false,
      runtimeOptions?.onTurnEvent
    );
    if (timed.status === "completed") {
      return {
        status: "completed",
        threadId,
        response: timed.response
      };
    }

    return {
      status: "timed_out",
      threadId,
      completion: handOffCompletion(timed.completion)
    };
  });
}

async function startThreadOnClient(
  client: { send: (method: string, params: unknown) => Promise<unknown> },
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

function parseThreadListPage(result: unknown): { threads: ThreadSummary[]; nextCursor: string | null } {
  const data = asArray(asObject(result).data);
  const nextCursor = getString(asObject(result).nextCursor);
  const threads: ThreadSummary[] = [];

  for (const entry of data) {
    const thread = asObject(entry);
    const id = getString(thread.id);
    const cwd = getString(thread.cwd);
    const preview = getString(thread.preview) ?? "";
    const createdAt = getNumber(thread.createdAt);
    const updatedAt = getNumber(thread.updatedAt);

    if (!id || !cwd || createdAt === null || updatedAt === null) {
      continue;
    }

    threads.push({
      id,
      cwd,
      preview,
      createdAt,
      updatedAt,
      path: getString(thread.path),
      source: normalizeSource(thread.source)
    });
  }

  return { threads, nextCursor };
}

function buildThreadListParams(limit: number, cursor: string | null): Record<string, unknown> {
  return {
    limit: Math.max(1, Math.trunc(limit)),
    sortKey: "updated_at",
    sourceKinds: Array.from(THREAD_LIST_SOURCE_KINDS),
    cursor
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

function buildThreadStartParams(options: ConversationOptions): Record<string, unknown> {
  const params: Record<string, unknown> = {
    cwd: options.cwd
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
): Record<string, unknown> | null {
  const overrides: Record<string, unknown> = {};

  if (networkAccessEnabled !== null && networkAccessEnabled !== undefined) {
    overrides.sandbox_workspace_write = {
      network_access: networkAccessEnabled
    };
  }

  if (skipGitRepoCheck !== null && skipGitRepoCheck !== undefined) {
    overrides.ignore_git_repo_check = skipGitRepoCheck;
  }

  return Object.keys(overrides).length ? overrides : null;
}
