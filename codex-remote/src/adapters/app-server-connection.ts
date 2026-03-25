import { spawn } from "node:child_process";
import {
  ApprovalDecision,
  ApprovalRequest,
  CODEXHUB_BIN,
  DEFAULT_OPT_OUT_NOTIFICATION_METHODS,
  TurnRuntimeOptions
} from "./app-server-client-types.js";
import { asArray, asObject, getString } from "./app-server-json.js";

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

export type JsonRpcNotification = {
  method: string;
  params?: unknown;
};

type JsonRpcRequest = {
  id: string | number;
  method: string;
  params?: unknown;
};

type JsonRpcMessage = JsonRpcSuccess | JsonRpcError | JsonRpcNotification | JsonRpcRequest;

type NotificationHandler = (notification: JsonRpcNotification) => void;

export class AppServerConnection {
  private readonly child = spawn(CODEXHUB_BIN, ["app-server", "--listen", "stdio://"], {
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

export async function withAppServer<T>(work: (client: AppServerConnection) => Promise<T>): Promise<T> {
  const client = new AppServerConnection();
  try {
    await client.initialize();
    return await work(client);
  } finally {
    await client.close();
  }
}

export async function withTurnClient<T>(
  runtimeOptions: TurnRuntimeOptions | undefined,
  work: (
    client: AppServerConnection,
    handOffCompletion: (completion: Promise<{ response: string }>) => Promise<{ response: string }>
  ) => Promise<T>
): Promise<T> {
  const client = new AppServerConnection(runtimeOptions);
  await client.initialize();

  let handedOff = false;
  const handOffCompletion = (completion: Promise<{ response: string }>): Promise<{ response: string }> => {
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
