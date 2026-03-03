import { spawn } from "node:child_process";
import process from "node:process";

type JsonRpcSuccess = {
  id: number;
  result: unknown;
};

type JsonRpcError = {
  id: number;
  error: {
    code: number;
    message: string;
    data?: unknown;
  };
};

type JsonRpcNotification = {
  method: string;
  params?: unknown;
};

type JsonRpcRequest = {
  id: string | number;
  method: string;
  params?: unknown;
};

type JsonRpcMessage = JsonRpcSuccess | JsonRpcError | JsonRpcNotification | JsonRpcRequest;

type ConversationOptions = {
  cwd: string;
  model?: string;
  approvalPolicy?: ApprovalPolicy;
  sandboxMode?: SandboxMode;
  networkAccessEnabled?: boolean | null;
  skipGitRepoCheck?: boolean | null;
};

export type ApprovalPolicy = "never" | "on-request" | "on-failure" | "untrusted";
export type SandboxMode = "read-only" | "workspace-write" | "danger-full-access";
export type ApprovalDecision = "accept" | "acceptForSession" | "decline" | "cancel";

export type ApprovalRequest = {
  method: "item/commandExecution/requestApproval" | "item/fileChange/requestApproval";
  threadId: string;
  turnId: string;
  itemId: string;
  approvalId: string | null;
  reason: string | null;
  command: string | null;
  cwd: string | null;
};

export type AgentTextSnapshot = {
  itemId: string;
  text: string;
};

type TurnRuntimeOptions = {
  approvalHandler?: (request: ApprovalRequest) => Promise<ApprovalDecision>;
  onAgentTextSnapshot?: (snapshot: AgentTextSnapshot) => void;
};

const TURN_TIMEOUT_MS = 5 * 60 * 1000;
const THREAD_LIST_SOURCE_KINDS = ["vscode", "cli", "appServer"] as const;

export type ThreadSummary = {
  id: string;
  cwd: string;
  preview: string;
  createdAt: number;
  updatedAt: number;
  path: string | null;
  source: string;
};

type TurnCompletion = {
  response: string;
};

export type TimedTurnResult =
  | {
      status: "completed";
      response: string;
    }
  | {
      status: "timed_out";
      completion: Promise<TurnCompletion>;
    };

export type TimedCreateTurnResult =
  | {
      status: "completed";
      conversationId: string;
      response: string;
    }
  | {
      status: "timed_out";
      conversationId: string;
      completion: Promise<TurnCompletion>;
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

export async function findThreadById(threadId: string, maxToScan = 500): Promise<ThreadSummary | null> {
  return withAppServer(async (client) => {
    const scanLimit = Math.max(1, Math.trunc(maxToScan));
    let scanned = 0;
    let cursor: string | null = null;

    while (scanned < scanLimit) {
      const pageLimit = Math.min(100, scanLimit - scanned);
      const result = await client.send("thread/list", buildThreadListParams(pageLimit, cursor));
      const page = parseThreadListPage(result);

      const match = page.threads.find((thread) => thread.id === threadId);
      if (match) {
        return match;
      }

      scanned += page.threads.length;
      if (!page.nextCursor || page.threads.length === 0) {
        return null;
      }
      cursor = page.nextCursor;
    }

    return null;
  });
}

export async function sendMessageWithTimeoutContinuation(
  conversationId: string,
  text: string,
  runtimeOptions?: TurnRuntimeOptions
): Promise<TimedTurnResult> {
  return sendMessageWithTimeoutContinuationInternal(conversationId, text, true, runtimeOptions);
}

export async function sendMessageWithoutResumeWithTimeoutContinuation(
  conversationId: string,
  text: string,
  runtimeOptions?: TurnRuntimeOptions
): Promise<TimedTurnResult> {
  return sendMessageWithTimeoutContinuationInternal(conversationId, text, false, runtimeOptions);
}

async function sendMessageWithTimeoutContinuationInternal(
  conversationId: string,
  text: string,
  resumeFirst: boolean,
  runtimeOptions?: TurnRuntimeOptions
): Promise<TimedTurnResult> {
  const client = new AppServerConnection(runtimeOptions);
  await client.initialize();

  let handedOff = false;
  try {
    const completion = runTurn(
      client,
      conversationId,
      text,
      resumeFirst,
      runtimeOptions?.onAgentTextSnapshot
    );
    const raced = await waitWithTimeout(completion, TURN_TIMEOUT_MS);
    if (raced.status === "completed") {
      return {
        status: "completed",
        response: raced.value
      };
    }

    handedOff = true;
    return {
      status: "timed_out",
      completion: completion
        .then((response) => ({ response }))
        .finally(async () => {
          await client.close();
        })
    };
  } catch (error) {
    await client.close();
    throw error;
  } finally {
    if (!handedOff) {
      await client.close();
    }
  }
}

export async function createAndSendFirstMessageWithTimeoutContinuation(
  options: ConversationOptions,
  text: string,
  runtimeOptions?: TurnRuntimeOptions
): Promise<TimedCreateTurnResult> {
  const client = new AppServerConnection(runtimeOptions);
  await client.initialize();

  let handedOff = false;
  try {
    const conversationId = await startConversationOnClient(client, options);

    const completion = runTurn(
      client,
      conversationId,
      text,
      false,
      runtimeOptions?.onAgentTextSnapshot
    );
    const raced = await waitWithTimeout(completion, TURN_TIMEOUT_MS);
    if (raced.status === "completed") {
      return {
        status: "completed",
        conversationId,
        response: raced.value
      };
    }

    handedOff = true;
    return {
      status: "timed_out",
      conversationId,
      completion: completion
        .then((response) => ({ response }))
        .finally(async () => {
          await client.close();
        })
    };
  } catch (error) {
    await client.close();
    throw error;
  } finally {
    if (!handedOff) {
      await client.close();
    }
  }
}

type NotificationHandler = (notification: JsonRpcNotification) => void;

class AppServerConnection {
  private readonly child = spawn("codex", ["app-server", "--listen", "stdio://"], {
    stdio: ["pipe", "pipe", "pipe"],
    env: process.env
  });

  private readonly handlers = new Set<NotificationHandler>();
  private readonly pending = new Map<
    number | string,
    { resolve: (value: unknown) => void; reject: (error: unknown) => void }
  >();
  private nextId = 1;
  private buffer = "";

  constructor(private readonly runtimeOptions?: TurnRuntimeOptions) {
    this.child.stdout.setEncoding("utf8");
    this.child.stdout.on("data", (chunk: string) => {
      this.buffer += chunk;
      this.processBuffer();
    });

    this.child.stderr.on("data", () => {
      // Suppress noisy app-server warnings in bot output.
    });

    this.child.on("error", (error) => {
      this.failPending(error);
    });

    this.child.on("exit", () => {
      this.failPending(new Error("app-server process exited"));
    });
  }

  async initialize(): Promise<void> {
    await this.send("initialize", {
      clientInfo: {
        name: "telegram-gateway",
        title: null,
        version: "1.0"
      },
      capabilities: {
        experimentalApi: true
      }
    });
    this.notify("initialized");
  }

  async close(): Promise<void> {
    if (this.child.killed || this.child.exitCode !== null || this.child.signalCode !== null) {
      return;
    }

    await new Promise<void>((resolve) => {
      const done = () => resolve();
      this.child.once("exit", done);
      this.child.kill("SIGTERM");
      const forceResolve = setTimeout(() => {
        resolve();
      }, 1500);
      setTimeout(() => {
        if (!this.child.killed) {
          this.child.kill("SIGKILL");
        }
      }, 1000);
      this.child.once("exit", () => clearTimeout(forceResolve));
    });
  }

  onNotification(handler: NotificationHandler): () => void {
    this.handlers.add(handler);
    return () => {
      this.handlers.delete(handler);
    };
  }

  async send(method: string, params: unknown): Promise<unknown> {
    const id = this.nextId++;
    const payload = {
      jsonrpc: "2.0",
      id,
      method,
      params
    };

    const result = new Promise<unknown>((resolve, reject) => {
      this.pending.set(id, { resolve, reject });
    });

    this.child.stdin.write(`${JSON.stringify(payload)}\n`);
    return result;
  }

  notify(method: string, params?: unknown): void {
    const payload = {
      jsonrpc: "2.0",
      method,
      ...(params === undefined ? {} : { params })
    };
    this.child.stdin.write(`${JSON.stringify(payload)}\n`);
  }

  private processBuffer(): void {
    while (true) {
      const index = this.buffer.indexOf("\n");
      if (index < 0) {
        return;
      }

      const line = this.buffer.slice(0, index).trim();
      this.buffer = this.buffer.slice(index + 1);

      if (!line) {
        continue;
      }

      let parsed: JsonRpcMessage;
      try {
        parsed = JSON.parse(line) as JsonRpcMessage;
      } catch {
        continue;
      }

      if ("method" in parsed) {
        if ("id" in parsed) {
          void this.handleServerRequest(parsed)
            .then((result) => {
              this.respondSuccess(parsed.id, result);
            })
            .catch((error) => {
              const message = error instanceof Error ? error.message : String(error);
              this.respondError(parsed.id, -32000, message);
            });
          continue;
        }

        for (const handler of this.handlers) {
          handler(parsed);
        }
        continue;
      }

      if (!("id" in parsed)) {
        continue;
      }

      const waiter = this.pending.get(parsed.id);
      if (!waiter) {
        continue;
      }
      this.pending.delete(parsed.id);

      if ("error" in parsed) {
        const message = parsed.error?.message ?? "Unknown app-server error";
        waiter.reject(new Error(message));
        continue;
      }

      waiter.resolve(parsed.result);
    }
  }

  private async handleServerRequest(request: JsonRpcRequest): Promise<unknown> {
    if (request.method === "execCommandApproval" || request.method === "applyPatchApproval") {
      const decision = await this.requestDecisionFromHandler(
        toLegacyApprovalRequest(request.method, request.params)
      );
      return { decision: mapLegacyApprovalDecision(decision) };
    }

    if (request.method === "item/commandExecution/requestApproval") {
      const decision = await this.requestDecisionFromHandler(
        toV2ApprovalRequest(request.method, request.params)
      );
      return { decision };
    }

    if (request.method === "item/fileChange/requestApproval") {
      const decision = await this.requestDecisionFromHandler(
        toV2ApprovalRequest(request.method, request.params)
      );
      return { decision };
    }

    if (request.method === "item/tool/requestUserInput") {
      return {
        answers: buildEmptyToolInputAnswers(asArray(asObject(request.params).questions))
      };
    }

    if (request.method === "item/tool/call") {
      return {
        success: false,
        contentItems: [
          {
            type: "inputText",
            text: "Dynamic tool calls are not supported by this Telegram gateway."
          }
        ]
      };
    }

    if (request.method === "account/chatgptAuthTokens/refresh") {
      throw new Error("ChatGPT auth token refresh is not supported in this gateway runtime.");
    }

    throw new Error(`Unsupported server request method: ${request.method}`);
  }

  private async requestDecisionFromHandler(request: ApprovalRequest | null): Promise<ApprovalDecision> {
    if (!request || !this.runtimeOptions?.approvalHandler) {
      return "decline";
    }

    try {
      return await this.runtimeOptions.approvalHandler(request);
    } catch {
      return "decline";
    }
  }

  private respondSuccess(id: string | number, result: unknown): void {
    const payload = {
      jsonrpc: "2.0",
      id,
      result
    };
    this.child.stdin.write(`${JSON.stringify(payload)}\n`);
  }

  private respondError(id: string | number, code: number, message: string): void {
    const payload = {
      jsonrpc: "2.0",
      id,
      error: {
        code,
        message
      }
    };
    this.child.stdin.write(`${JSON.stringify(payload)}\n`);
  }

  private failPending(error: unknown): void {
    for (const [id, waiter] of this.pending.entries()) {
      this.pending.delete(id);
      waiter.reject(error);
    }
  }
}

async function withAppServer<T>(work: (client: AppServerConnection) => Promise<T>): Promise<T> {
  const client = new AppServerConnection();
  try {
    await client.initialize();
    return await work(client);
  } finally {
    await client.close();
  }
}

async function runTurn(
  client: AppServerConnection,
  conversationId: string,
  text: string,
  resumeFirst: boolean,
  onAgentTextSnapshot?: (snapshot: AgentTextSnapshot) => void
): Promise<string> {
  if (resumeFirst) {
    await client.send("thread/resume", {
      threadId: conversationId
    });
  }

  let lastAgentMessage = "";
  let currentTurnId: string | null = null;
  let finished = false;
  let resolveTurn: (value: string) => void = () => {};
  let rejectTurn: (reason: unknown) => void = () => {};

  const turnDone = new Promise<string>((resolve, reject) => {
    resolveTurn = resolve;
    rejectTurn = reject;
  });

  const finalizeSuccess = (value: string): void => {
    if (finished) {
      return;
    }
    finished = true;
    resolveTurn(value);
  };

  const finalizeFailure = (error: unknown): void => {
    if (finished) {
      return;
    }
    finished = true;
    rejectTurn(error);
  };

  const agentSnapshots = new Map<string, string>();

  const emitSnapshot = (snapshot: AgentTextSnapshot): void => {
    if (!onAgentTextSnapshot) {
      return;
    }
    try {
      onAgentTextSnapshot(snapshot);
    } catch {
      // Snapshot consumers are best-effort and must not break turn handling.
    }
  };

  const detachNotification = client.onNotification((notification) => {
    const params = asObject(notification.params);

    const eventThreadId = getString(params.threadId);
    if (eventThreadId !== conversationId) {
      return;
    }

    if (notification.method === "item/agentMessage/delta") {
      if (!currentTurnId) {
        return;
      }
      const eventTurnId = getString(params.turnId);
      if (!eventTurnId || eventTurnId !== currentTurnId) {
        return;
      }

      const delta = getString(params.delta);
      if (delta) {
        const itemId = getString(params.itemId) ?? "agent-message";
        const currentSnapshot = agentSnapshots.get(itemId) ?? "";
        const nextSnapshot = currentSnapshot + delta;
        agentSnapshots.set(itemId, nextSnapshot);
        lastAgentMessage = nextSnapshot;
        emitSnapshot({ itemId, text: nextSnapshot });
      }
      return;
    }

    if (notification.method === "item/completed") {
      if (!currentTurnId) {
        return;
      }
      const eventTurnId = getString(params.turnId);
      if (!eventTurnId || eventTurnId !== currentTurnId) {
        return;
      }

      const item = asObject(params.item);
      if (getString(item.type) !== "agentMessage") {
        return;
      }

      const text = getString(item.text);
      if (text !== null) {
        lastAgentMessage = text;
        const itemId = getString(item.id) ?? getString(params.itemId) ?? "agent-message";
        agentSnapshots.set(itemId, text);
        emitSnapshot({ itemId, text });
      }
      return;
    }

    if (notification.method !== "turn/completed") {
      return;
    }

    const turn = asObject(params.turn);
    const eventTurnId = getString(turn.id);
    if (!currentTurnId || !eventTurnId || eventTurnId !== currentTurnId) {
      return;
    }

    const status = getString(turn.status);
    if (status === "completed") {
      finalizeSuccess(lastAgentMessage.trim());
      return;
    }

    if (status === "interrupted") {
      const trimmed = lastAgentMessage.trim();
      if (trimmed) {
        finalizeSuccess(trimmed);
        return;
      }
      finalizeFailure(new Error("Turn was interrupted before producing a response."));
      return;
    }

    if (status === "failed") {
      finalizeFailure(new Error(getTurnFailureMessage(turn)));
      return;
    }

    if (status === "inProgress") {
      return;
    }

    finalizeFailure(new Error(`Turn ended with unexpected status: ${status ?? "unknown"}`));
  });

  try {
    const started = await client.send("turn/start", {
      threadId: conversationId,
      input: [
        {
          type: "text",
          text
        }
      ]
    });

    const startedTurn = asObject(asObject(started).turn);
    currentTurnId = getString(startedTurn.id);

    const status = getString(startedTurn.status);
    if (status === "completed") {
      return lastAgentMessage.trim();
    }
    if (status === "failed") {
      throw new Error(getTurnFailureMessage(startedTurn));
    }
    if (status === "interrupted") {
      throw new Error("Turn was interrupted before completion.");
    }
    if (status && status !== "inProgress") {
      throw new Error(`Turn started with unexpected status: ${status}`);
    }

    return await turnDone;
  } finally {
    detachNotification();
  }
}

async function waitWithTimeout<T>(
  promise: Promise<T>,
  timeoutMs: number
): Promise<{ status: "completed"; value: T } | { status: "timed_out" }> {
  let timeoutHandle: NodeJS.Timeout | null = null;
  try {
    const timeoutPromise = new Promise<{ status: "timed_out" }>((resolve) => {
      timeoutHandle = setTimeout(() => {
        resolve({ status: "timed_out" });
      }, timeoutMs);
    });

    const completedPromise = promise.then((value) => ({ status: "completed" as const, value }));
    return await Promise.race([completedPromise, timeoutPromise]);
  } finally {
    if (timeoutHandle) {
      clearTimeout(timeoutHandle);
    }
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

function buildEmptyToolInputAnswers(questions: unknown[]): Record<string, { answers: string[] }> {
  const answers: Record<string, { answers: string[] }> = {};
  for (const question of questions) {
    const questionId = getString(asObject(question).id);
    if (!questionId) {
      continue;
    }
    answers[questionId] = { answers: [] };
  }
  return answers;
}

function toV2ApprovalRequest(
  method: "item/commandExecution/requestApproval" | "item/fileChange/requestApproval",
  paramsValue: unknown
): ApprovalRequest | null {
  const params = asObject(paramsValue);
  const threadId = getString(params.threadId);
  const turnId = getString(params.turnId);
  const itemId = getString(params.itemId);
  if (!threadId || !turnId || !itemId) {
    return null;
  }

  return {
    method,
    threadId,
    turnId,
    itemId,
    approvalId: getString(params.approvalId),
    reason: getString(params.reason),
    command: getString(params.command),
    cwd: getString(params.cwd)
  };
}

function toLegacyApprovalRequest(
  method: "execCommandApproval" | "applyPatchApproval",
  paramsValue: unknown
): ApprovalRequest | null {
  const params = asObject(paramsValue);
  const threadId = getString(params.conversationId);
  const callId = getString(params.callId);
  if (!threadId || !callId) {
    return null;
  }

  let command: string | null = null;
  const cmd = params.command;
  if (Array.isArray(cmd)) {
    const parts = cmd.filter((part): part is string => typeof part === "string");
    if (parts.length) {
      command = parts.join(" ");
    }
  }

  return {
    method: method === "execCommandApproval" ? "item/commandExecution/requestApproval" : "item/fileChange/requestApproval",
    threadId,
    turnId: callId,
    itemId: callId,
    approvalId: getString(params.approvalId),
    reason: getString(params.reason),
    command,
    cwd: getString(params.cwd)
  };
}

function mapLegacyApprovalDecision(decision: ApprovalDecision): "approved" | "approved_for_session" | "denied" | "abort" {
  if (decision === "accept") {
    return "approved";
  }
  if (decision === "acceptForSession") {
    return "approved_for_session";
  }
  if (decision === "cancel") {
    return "abort";
  }
  return "denied";
}

function getTurnFailureMessage(turn: Record<string, unknown>): string {
  const error = asObject(turn.error);
  const message = getString(error.message);
  const details = getString(error.additionalDetails);

  if (message && details) {
    return `${message}\n${details}`;
  }
  if (message) {
    return message;
  }
  return "Turn failed.";
}

function asObject(value: unknown): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    return {};
  }
  return value as Record<string, unknown>;
}

function asArray(value: unknown): unknown[] {
  if (!Array.isArray(value)) {
    return [];
  }
  return value;
}

function getString(value: unknown): string | null {
  if (typeof value !== "string") {
    return null;
  }
  const trimmed = value.trim();
  return trimmed ? trimmed : null;
}

function getNumber(value: unknown): number | null {
  if (typeof value !== "number" || !Number.isFinite(value)) {
    return null;
  }
  return value;
}

async function startConversationOnClient(
  client: AppServerConnection,
  options: ConversationOptions
): Promise<string> {
  const result = await client.send("thread/start", buildThreadStartParams(options));
  const thread = asObject(result).thread;
  const conversationId = asObject(thread).id;
  if (typeof conversationId !== "string" || !conversationId) {
    throw new Error("app-server thread/start did not return a thread id");
  }
  return conversationId;
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
