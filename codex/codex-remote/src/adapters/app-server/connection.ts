import { spawn } from "node:child_process";
import {
  CODEX_CORE_BIN,
  DEFAULT_OPT_OUT_NOTIFICATION_METHODS,
  TurnRuntimeOptions,
} from "./types.js";
import {
  JsonRpcMessage,
  JsonRpcNotification,
  JsonRpcRequest,
  NotificationHandler,
} from "./protocol.js";
import { handleServerRequest } from "./server-requests.js";

export { type JsonRpcNotification } from "./protocol.js";

export class AppServerConnection {
  private readonly child = spawn(CODEX_CORE_BIN, ["app-server", "--listen", "stdio://"], {
    stdio: ["pipe", "pipe", "pipe"],
    env: process.env,
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
        version: "1.0",
      },
      capabilities: {
        experimentalApi: true,
        optOutNotificationMethods: Array.from(DEFAULT_OPT_OUT_NOTIFICATION_METHODS),
      },
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
    const result = new Promise<unknown>((resolve, reject) => {
      this.pending.set(id, { resolve, reject });
    });

    this.writeMessage({
      jsonrpc: "2.0",
      id,
      method,
      params,
    });
    return result;
  }

  notify(method: string, params?: unknown): void {
    this.writeMessage({
      jsonrpc: "2.0",
      method,
      ...(params === undefined ? {} : { params }),
    });
  }

  private writeMessage(payload: unknown): void {
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

      const parsed = this.parseMessage(line);
      if (!parsed) {
        continue;
      }

      this.handleMessage(parsed);
    }
  }

  private parseMessage(line: string): JsonRpcMessage | null {
    try {
      return JSON.parse(line) as JsonRpcMessage;
    } catch {
      return null;
    }
  }

  private handleMessage(message: JsonRpcMessage): void {
    if ("method" in message) {
      if ("id" in message) {
        this.handleIncomingRequest(message);
      } else {
        this.dispatchNotification(message);
      }
      return;
    }

    if ("id" in message) {
      this.resolvePending(message);
    }
  }

  private handleIncomingRequest(request: JsonRpcRequest): void {
    void handleServerRequest(request, this.runtimeOptions)
      .then((result) => {
        this.respondSuccess(request.id, result);
      })
      .catch((error) => {
        const message = error instanceof Error ? error.message : String(error);
        this.respondError(request.id, -32000, message);
      });
  }

  private dispatchNotification(notification: JsonRpcNotification): void {
    for (const handler of this.handlers) {
      handler(notification);
    }
  }

  private resolvePending(message: JsonRpcMessage): void {
    if (!("id" in message) || !("result" in message || "error" in message)) {
      return;
    }

    const waiter = this.pending.get(message.id);
    if (!waiter) {
      return;
    }
    this.pending.delete(message.id);

    if ("error" in message) {
      const errorMessage = message.error?.message ?? "Unknown app-server error";
      waiter.reject(new Error(errorMessage));
      return;
    }

    waiter.resolve(message.result);
  }

  private respondSuccess(id: string | number, result: unknown): void {
    this.writeMessage({
      jsonrpc: "2.0",
      id,
      result,
    });
  }

  private respondError(id: string | number, code: number, message: string): void {
    this.writeMessage({
      jsonrpc: "2.0",
      id,
      error: {
        code,
        message,
      },
    });
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
