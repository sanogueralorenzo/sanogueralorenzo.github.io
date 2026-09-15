import type { PromptContext, ReplyMarkup } from "./context.js";

export function topicIdFromContext(ctx: PromptContext): number {
  return ctx.message.message_thread_id ?? 0;
}

export function hasForumTopic(ctx: PromptContext): boolean {
  return topicIdFromContext(ctx) > 0;
}

export function topicKeyFromContext(ctx: PromptContext): string {
  return String(ctx.chat.id) + ":" + topicIdFromContext(ctx);
}

export function topicReply(
  ctx: PromptContext,
  text: string,
  options?: { reply_markup?: ReplyMarkup }
): Promise<unknown> {
  const topicId = ctx.message.message_thread_id;
  return ctx.api.sendMessage(ctx.chat.id, text, {
    ...(options ?? {}),
    ...(topicId === undefined ? {} : { message_thread_id: topicId }),
  });
}

export function topicMessageOptions(ctx: PromptContext): { message_thread_id?: number } {
  const topicId = ctx.message.message_thread_id;
  return topicId === undefined ? {} : { message_thread_id: topicId };
}
