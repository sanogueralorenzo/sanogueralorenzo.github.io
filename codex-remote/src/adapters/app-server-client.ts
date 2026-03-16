import { spawn } from "node:child_process";
import process from "node:process";

type JsonRpcSuccess = {
  id: number | string;
  result: unknown;
};

type JsonRpcError = {
  id: number | string;
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

export type TurnProgressEvent =
  | {
      kind: "itemStarted";
      threadId: string;
      turnId: string;
      itemId: string;
      itemType: string;
      command: string | null;
    }
  | {
      kind: "itemCompleted";
      threadId: string;
      turnId: string;
      itemId: string;
      itemType: string;
      text: string | null;
      status: string | null;
      command: string | null;
      output: string | null;
    }
  | {
      kind: "agentDelta" | "commandOutputDelta";
      threadId: string;
      turnId: string;
      itemId: string;
      itemType: string;
      text: string;
    };

type TurnRuntimeOptions = {
  approvalHandler?: (request: ApprovalRequest) => Promise<ApprovalDecision>;
  onTurnEvent?: (event: TurnProgressEvent) => void;
};

const TURN_TIMEOUT_MS = 5 * 60 * 1000;
const CODEX_APP_SERVER_BIN = process.env.CODEX_APP_SERVER_BIN?.trim() || "codex-app-server";
const THREAD_LIST_SOURCE_KINDS = ["vscode", "cli", "appServer"] as const;

// Keep transport-side policy in the app-server stream itself; clients focus on rendering.
const DEFAULT_OPT_OUT_NOTIFICATION_METHODS = [
  "item/reasoning/summaryTextDelta",
  "item/reasoning/summaryPartAdded",
  "item/reasoning/textDelta",
  "item/plan/delta",
  "turn/plan/updated",
  "rawResponseItem/completed"
] as const;

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
      threadId: string;
      response: string;
    }
  | {
      status: "timed_out";
      threadId: string;
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

type NotificationHandler = (notification: JsonRpcNotification) => void;

class AppServerConnection {
  private readonly child = spawn(CODEX_APP_SERVER_BIN, ["rpc", "--listen", "stdio://"], {
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
        name: "telegram-codex-remote",
        title: null,
        version: "1.0"
      },
      capabilities: {
        experimentalApi: true,
        optOutNotificationMethods: Array.from(DEFAULT_OPT_OUT_NOTIFICATION_METHODS)
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
    switch (request.method) {
      case "execCommandApproval":
      case "applyPatchApproval": {
        const decision = await this.requestDecisionFromHandler(
          toLegacyApprovalRequest(request.method, request.params)
        );
        return { decision: mapLegacyApprovalDecision(decision) };
      }
      case "item/commandExecution/requestApproval":
      case "item/fileChange/requestApproval": {
        const decision = await this.requestDecisionFromHandler(
          toV2ApprovalRequest(request.method, request.params)
        );
        return { decision };
      }
      case "item/tool/requestUserInput":
        return {
          answers: buildEmptyToolInputAnswers(asArray(asObject(request.params).questions))
        };
      case "item/tool/call":
        return {
          success: false,
          contentItems: [
            {
              type: "inputText",
              text: "Dynamic tool calls are not supported by this Telegram codex-remote runtime."
            }
          ]
        };
      case "account/chatgptAuthTokens/refresh":
        throw new Error("ChatGPT auth token refresh is not supported in this codex-remote runtime.");
      default:
        throw new Error(`Unsupported server request method: ${request.method}`);
    }
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

async function withTurnClient<T>(
  runtimeOptions: TurnRuntimeOptions | undefined,
  work: (
    client: AppServerConnection,
    handOffCompletion: (completion: Promise<TurnCompletion>) => Promise<TurnCompletion>
  ) => Promise<T>
): Promise<T> {
  const client = new AppServerConnection(runtimeOptions);
  await client.initialize();

  let handedOff = false;
  const handOffCompletion = (completion: Promise<TurnCompletion>): Promise<TurnCompletion> => {
    handedOff = true;
    return completion.finally(async () => {
      await client.close();
    });
  };

  try {
    return await work(client, handOffCompletion);
  } catch (error) {
    await client.close();
    throw error;
  } finally {
    if (!handedOff) {
      await client.close();
    }
  }
}

async function runTurnWithTimeout(
  client: AppServerConnection,
  threadId: string,
  text: string,
  resumeFirst: boolean,
  onTurnEvent?: (event: TurnProgressEvent) => void
): Promise<
  | { status: "completed"; response: string }
  | { status: "timed_out"; completion: Promise<TurnCompletion> }
> {
  const completion = runTurn(client, threadId, text, resumeFirst, onTurnEvent);
  const raced = await waitWithTimeout(completion, TURN_TIMEOUT_MS);
  if (raced.status === "completed") {
    return {
      status: "completed",
      response: raced.value
    };
  }

  return {
    status: "timed_out",
    completion: completion.then((response) => ({ response }))
  };
}

type RunTurnState = {
  threadId: string;
  currentTurnId: string | null;
  lastAgentMessage: string;
  lastFinalAgentMessage: string;
  agentSnapshots: Map<string, string>;
  emitTurnEvent: (event: TurnProgressEvent) => void;
  finalizeSuccess: (value: string) => void;
  finalizeFailure: (error: unknown) => void;
};

async function runTurn(
  client: AppServerConnection,
  threadId: string,
  text: string,
  resumeFirst: boolean,
  onTurnEvent?: (event: TurnProgressEvent) => void
): Promise<string> {
  if (resumeFirst) {
    await client.send("thread/resume", {
      threadId
    });
  }

  let finished = false;
  let resolveTurn: (value: string) => void = () => {};
  let rejectTurn: (reason: unknown) => void = () => {};
  const turnDone = new Promise<string>((resolve, reject) => {
    resolveTurn = resolve;
    rejectTurn = reject;
  });

  const state: RunTurnState = {
    threadId,
    currentTurnId: null,
    lastAgentMessage: "",
    lastFinalAgentMessage: "",
    agentSnapshots: new Map<string, string>(),
    emitTurnEvent: (event) => {
      if (!onTurnEvent) {
        return;
      }
      try {
        onTurnEvent(event);
      } catch {
        // Progress consumers are best-effort and must not break turn handling.
      }
    },
    finalizeSuccess: (value) => {
      if (finished) {
        return;
      }
      finished = true;
      resolveTurn(value);
    },
    finalizeFailure: (error) => {
      if (finished) {
        return;
      }
      finished = true;
      rejectTurn(error);
    }
  };

  const detachNotification = client.onNotification((notification) => {
    handleTurnNotification(state, notification);
  });

  try {
    const started = await client.send("turn/start", {
      threadId,
      input: [
        {
          type: "text",
          text
        }
      ]
    });

    const startedTurn = asObject(asObject(started).turn);
    state.currentTurnId = getString(startedTurn.id);

    const status = getString(startedTurn.status);
    if (status === "completed") {
      return latestTurnResponse(state);
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

function handleTurnNotification(state: RunTurnState, notification: JsonRpcNotification): void {
  const params = asObject(notification.params);
  if (!isTurnNotificationForThread(state, params)) {
    return;
  }
  if (!isTurnNotificationForCurrentTurn(state, params)) {
    return;
  }

  switch (notification.method) {
    case "turn/started": {
      const turn = asObject(params.turn);
      const turnId = getString(turn.id);
      if (turnId) {
        state.currentTurnId = turnId;
      }
      return;
    }
    case "item/started":
      handleItemStartedNotification(state, params);
      return;
    case "item/agentMessage/delta":
      handleAgentDeltaNotification(state, params);
      return;
    case "item/completed":
      handleItemCompletedNotification(state, params);
      return;
    case "turn/completed":
      handleTurnCompletedNotification(state, params);
      return;
    default:
      handleOutputDeltaNotification(state, notification.method, params);
  }
}

function isTurnNotificationForThread(state: RunTurnState, params: Record<string, unknown>): boolean {
  const eventThreadId = getString(params.threadId) ?? getString(params.conversationId);
  return eventThreadId === state.threadId;
}

function isTurnNotificationForCurrentTurn(state: RunTurnState, params: Record<string, unknown>): boolean {
  const eventTurnId = getString(params.turnId);
  if (!state.currentTurnId && eventTurnId) {
    state.currentTurnId = eventTurnId;
  }
  return !!state.currentTurnId && (!eventTurnId || eventTurnId === state.currentTurnId);
}

function handleItemStartedNotification(state: RunTurnState, params: Record<string, unknown>): void {
  const item = asObject(params.item);
  state.emitTurnEvent({
    kind: "itemStarted",
    threadId: state.threadId,
    turnId: state.currentTurnId!,
    itemId: getString(item.id) ?? getString(params.itemId) ?? "unknown-item",
    itemType: normalizeItemType(getString(item.type)),
    command: extractCommandText(item)
  });
}

function handleAgentDeltaNotification(state: RunTurnState, params: Record<string, unknown>): void {
  const delta = getString(params.delta);
  if (!delta) {
    return;
  }

  const itemId = getString(params.itemId) ?? "agent-message";
  const nextSnapshot = (state.agentSnapshots.get(itemId) ?? "") + delta;
  state.agentSnapshots.set(itemId, nextSnapshot);
  state.lastAgentMessage = nextSnapshot;
  state.emitTurnEvent({
    kind: "agentDelta",
    threadId: state.threadId,
    turnId: state.currentTurnId!,
    itemId,
    itemType: "agentMessage",
    text: delta
  });
}

function handleOutputDeltaNotification(
  state: RunTurnState,
  method: string,
  params: Record<string, unknown>
): void {
  if (!isCommandOutputDeltaMethod(method)) {
    return;
  }

  const delta = extractDeltaText(params);
  if (!delta) {
    return;
  }

  state.emitTurnEvent({
    kind: "commandOutputDelta",
    threadId: state.threadId,
    turnId: state.currentTurnId!,
    itemId: getString(params.itemId) ?? "unknown-item",
    itemType: extractDeltaItemType(method),
    text: delta
  });
}

function handleItemCompletedNotification(state: RunTurnState, params: Record<string, unknown>): void {
  const item = asObject(params.item);
  const itemId = getString(item.id) ?? getString(params.itemId) ?? "unknown-item";
  const itemType = normalizeItemType(getString(item.type));
  const text = extractItemText(item);

  if (itemType === "agentMessage" && text !== null) {
    state.lastAgentMessage = text;
    state.agentSnapshots.set(itemId, text);
    const phase = normalizeTextToken(getString(item.phase));
    if (phase === "finalanswer" || phase === "final") {
      state.lastFinalAgentMessage = text;
    }
  }

  state.emitTurnEvent({
    kind: "itemCompleted",
    threadId: state.threadId,
    turnId: state.currentTurnId!,
    itemId,
    itemType,
    text,
    status: extractItemStatus(item),
    command: extractCommandText(item),
    output: extractItemOutput(item)
  });
}

function handleTurnCompletedNotification(state: RunTurnState, params: Record<string, unknown>): void {
  const turn = asObject(params.turn);
  const completedTurnId = getString(turn.id);
  if (!state.currentTurnId || !completedTurnId || completedTurnId !== state.currentTurnId) {
    return;
  }

  const status = getString(turn.status);
  if (status === "completed") {
    state.finalizeSuccess(latestTurnResponse(state));
    return;
  }

  if (status === "interrupted") {
    const trimmed = latestTurnResponse(state);
    if (trimmed) {
      state.finalizeSuccess(trimmed);
      return;
    }
    state.finalizeFailure(new Error("Turn was interrupted before producing a response."));
    return;
  }

  if (status === "failed") {
    state.finalizeFailure(new Error(getTurnFailureMessage(turn)));
    return;
  }

  if (status === "inProgress") {
    return;
  }

  state.finalizeFailure(new Error(`Turn ended with unexpected status: ${status ?? "unknown"}`));
}

function latestTurnResponse(state: RunTurnState): string {
  return (state.lastFinalAgentMessage || state.lastAgentMessage).trim();
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
    method:
      method === "execCommandApproval" ? "item/commandExecution/requestApproval" : "item/fileChange/requestApproval",
    threadId,
    turnId: callId,
    itemId: callId,
    approvalId: getString(params.approvalId),
    reason: getString(params.reason),
    command,
    cwd: getString(params.cwd)
  };
}

function mapLegacyApprovalDecision(
  decision: ApprovalDecision
): "approved" | "approved_for_session" | "denied" | "abort" {
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

function isCommandOutputDeltaMethod(method: string): boolean {
  return (
    method === "item/fileChange/outputDelta" ||
    method === "item/commandExecution/outputDelta" ||
    method === "command/exec/outputDelta"
  );
}

function extractDeltaItemType(method: string): string {
  if (method === "item/fileChange/outputDelta") {
    return "fileChange";
  }
  if (method === "item/commandExecution/outputDelta" || method === "command/exec/outputDelta") {
    return "commandExecution";
  }
  return "unknown";
}

function extractDeltaText(params: Record<string, unknown>): string | null {
  return (
    getString(params.delta) ??
    getString(params.textDelta) ??
    getString(params.summaryTextDelta) ??
    getString(params.outputDelta) ??
    getString(params.text)
  );
}

function normalizeItemType(type: string | null): string {
  if (!type) {
    return "unknown";
  }
  const token = normalizeTextToken(type);
  switch (token) {
    case "agentmessage":
      return "agentMessage";
    case "usermessage":
      return "userMessage";
    case "reasoning":
      return "reasoning";
    case "plan":
      return "plan";
    case "commandexecution":
      return "commandExecution";
    case "filechange":
      return "fileChange";
    case "toolcall":
      return "toolCall";
    case "toolresult":
      return "toolResult";
    case "collabtoolcall":
      return "collabToolCall";
    default:
      return type;
  }
}

function extractItemStatus(item: Record<string, unknown>): string | null {
  const statusValue = item.status;
  if (typeof statusValue === "string") {
    return statusValue;
  }
  return getString(asObject(statusValue).type);
}

function extractCommandText(item: Record<string, unknown>): string | null {
  return getString(item.command);
}

function extractItemOutput(item: Record<string, unknown>): string | null {
  return getString(item.aggregatedOutput) ?? getString(item.aggregated_output) ?? getString(item.output);
}

function extractItemText(item: Record<string, unknown>): string | null {
  return getString(item.text) ?? getString(item.summary);
}

function normalizeTextToken(value: string | null): string {
  if (!value) {
    return "";
  }
  return value.toLowerCase().replace(/[^a-z0-9]/g, "");
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

async function startThreadOnClient(
  client: AppServerConnection,
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
