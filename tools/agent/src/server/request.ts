import type { IncomingMessage } from "node:http";
import type { Store } from "../conversation/store.js";
import type { Channel, TurnRequest } from "../conversation/types.js";

export async function readBody(request: IncomingMessage, limit: number): Promise<Buffer> {
  const chunks: Buffer[] = [];
  let size = 0;
  for await (const chunk of request) {
    const buffer = Buffer.from(chunk);
    size += buffer.length;
    if (size > limit) throw new Error("Request body is too large.");
    chunks.push(buffer);
  }
  return Buffer.concat(chunks);
}

export async function readJson(request: IncomingMessage): Promise<Record<string, unknown>> {
  const body = await readBody(request, 1_000_000);
  return body.length ? JSON.parse(body.toString("utf8")) as Record<string, unknown> : {};
}

export async function readTurn(request: IncomingMessage, store: Store): Promise<TurnRequest> {
  const body = await readJson(request);
  const text = typeof body.text === "string" ? body.text.trim() : "";
  if (body.attachmentIds !== undefined && (
    !Array.isArray(body.attachmentIds)
    || body.attachmentIds.length > 8
    || !body.attachmentIds.every((id) => typeof id === "string" && id.length > 0)
  )) throw new Error("attachmentIds must contain at most 8 IDs");
  const attachmentIds = (body.attachmentIds ?? []) as string[];
  if (!text && attachmentIds.length === 0) throw new Error("text or an attachment is required");
  const attachments = attachmentIds.map((id) => {
    const attachment = store.getAttachment(id);
    if (!attachment) throw new Error("attachment not found");
    return attachment;
  });
  const channel = body.channel as Channel;
  if (channel !== "telegram" && channel !== "macos" && channel !== "cli" && channel !== "api") throw new Error("channel must be cli, telegram, macos, or api");
  if (typeof body.sessionId !== "string" || !body.sessionId) throw new Error("sessionId is required");
  if (body.requestId !== undefined && (typeof body.requestId !== "string" || !/^[0-9a-f-]{36}$/i.test(body.requestId))) {
    throw new Error("requestId must be a UUID");
  }
  return {
    text,
    ...(typeof body.requestId === "string" ? { requestId: body.requestId } : {}),
    ...(attachmentIds.length ? { attachmentIds, attachments } : {}),
    ...(typeof body.cwd === "string" ? { cwd: body.cwd } : {}),
    sessionId: body.sessionId,
    channel,
  };
}
