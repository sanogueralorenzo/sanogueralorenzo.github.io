import {
  archiveThreadById,
  setThreadNameById,
} from "../adapters/app-server/client.js";
import { TopicStore } from "../adapters/topic-store.js";
import type { PromptContext } from "../bot/context.js";
import { hasForumTopic, topicIdFromContext, topicReply } from "../bot/topic.js";
import { formatFailure } from "../bot/messages.js";

const DEFAULT_TOPIC_TITLE = "Codex session";
const MAX_TOPIC_TITLE_LENGTH = 128;

type TopicActionsDeps = {
  store: TopicStore;
};

export function createTopicActions(deps: TopicActionsDeps) {
  async function createTopic(ctx: PromptContext, requestedTitle: string): Promise<void> {
    const title = normalizeTopicTitle(requestedTitle);
    const topic = await ctx.api.createForumTopic(ctx.chat.id, title);
    await ctx.api.sendMessage(
      ctx.chat.id,
      "Topic ready: " + topic.name + "\nSend a message to start its Codex session.",
      { message_thread_id: topic.message_thread_id }
    );
  }

  async function archiveTopic(ctx: PromptContext): Promise<void> {
    if (!hasForumTopic(ctx)) {
      await topicReply(ctx, "Use /archive inside a topic.");
      return;
    }

    const topicId = topicIdFromContext(ctx);
    const chatId = String(ctx.chat.id);
    const binding = await deps.store.get(chatId, topicId);
    if (binding) {
      await archiveThreadById(binding.threadId);
    }

    await topicReply(ctx, "Topic archived.");
    await ctx.api.closeForumTopic(ctx.chat.id, topicId);
    await deps.store.remove(chatId, topicId);
  }

  async function renameTopic(ctx: PromptContext, requestedTitle: string): Promise<void> {
    if (!hasForumTopic(ctx)) {
      await topicReply(ctx, "Use /rename <title> inside a topic.");
      return;
    }

    if (!requestedTitle.trim()) {
      await topicReply(ctx, "Usage: /rename <title>");
      return;
    }

    const title = normalizeTopicTitle(requestedTitle);
    const topicId = topicIdFromContext(ctx);
    const chatId = String(ctx.chat.id);
    const binding = await deps.store.get(chatId, topicId);
    await ctx.api.editForumTopic(ctx.chat.id, topicId, { name: title });
    if (binding) {
      await setThreadNameById(binding.threadId, title);
      await deps.store.set(chatId, topicId, { ...binding, title });
    }
    await topicReply(ctx, "Renamed to: " + title);
  }

  return {
    createTopic,
    archiveTopic,
    renameTopic,
  };
}

function normalizeTopicTitle(value: string): string {
  const title = value.trim() || DEFAULT_TOPIC_TITLE;
  return title.slice(0, MAX_TOPIC_TITLE_LENGTH);
}

export function topicActionFailure(prefix: string, error: unknown): string {
  return formatFailure(prefix, error instanceof Error ? error.message : String(error));
}
