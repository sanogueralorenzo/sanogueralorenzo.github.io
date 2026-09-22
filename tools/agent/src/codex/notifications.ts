import { CodexDisconnectedError } from "./app-server.js";
import type { JsonRpcMessage } from "./protocol.js";

export type Notifications = AsyncIterator<[JsonRpcMessage]>;

export function object(value: unknown): Record<string, unknown> {
  return value && typeof value === "object" ? value as Record<string, unknown> : {};
}

export function classifiedError(error: unknown): Error {
  const message = error instanceof Error ? error.message : String(error);
  if (/auth|login|token|unauthorized/i.test(message)) return new Error("Your Agent connection has expired. Sign in again to reconnect it.");
  if (/rate.?limit|usage.?limit|credits?.?depleted|allowance/i.test(message)) return new Error("Your current OpenAI allowance or credits are exhausted.");
  return error instanceof Error ? error : new Error(message);
}

export async function nextForThread(queue: Notifications, threadId: string) {
  while (true) {
    const { value } = await queue.next();
    const message = value![0];
    if (message.method === "agent/disconnected") {
      throw new CodexDisconnectedError(String(message.params?.message ?? "Codex disconnected."));
    }
    const params = object(message.params);
    if (params.threadId !== threadId) continue;
    if (message.method === "error" && params.willRetry !== true) {
      throw classifiedError(object(params.error).message ?? "The Codex turn failed.");
    }
    return { id: message.id, method: message.method, params };
  }
}
