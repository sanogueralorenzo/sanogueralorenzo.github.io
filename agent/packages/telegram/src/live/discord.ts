// Discord live connection implemented with discord.js.

import { once } from "node:events";

import { Client, Events, GatewayIntentBits, type Message, Partials } from "discord.js";

import type { DiscordAccountConfig, ResolvedConversation } from "../core/config-types.js";
import type { InboundMessageInput } from "../core/runtime-types.js";
import { chunkText } from "../render/chunking.js";
import { formatMarkdownForService, maxMessageLength } from "../render/format.js";
import { StreamingPreview } from "../render/streaming.js";
import { readLocalAttachment, storeDownloadedAttachment, textMentionsBot } from "./common.js";
import type { LiveConnection, LiveConnectionHandlers } from "./types.js";

async function withReadyClient(token: string): Promise<Client<true>> {
	const client = new Client({
		intents: [GatewayIntentBits.Guilds, GatewayIntentBits.GuildMessages, GatewayIntentBits.MessageContent],
		partials: [Partials.Channel],
	});
	const readyPromise = once(client, "ready");
	try {
		await client.login(token);
	} catch (error) {
		const message = error instanceof Error ? error.message : String(error);
		if (message.includes("Used disallowed intents")) {
			throw new Error(
				'Discord rejected the configured gateway intents. Enable the "Message Content Intent" in the Discord Developer Portal under Bot settings, then reconnect.',
			);
		}
		throw error;
	}
	if (!client.isReady()) {
		await Promise.race([
			readyPromise,
			new Promise((_, reject) => setTimeout(() => reject(new Error("Discord client failed to become ready")), 10000)),
		]);
	}
	if (!client.isReady()) throw new Error("Discord client failed to become ready");
	return client as Client<true>;
}

function getTargetChannelId(conversation: ResolvedConversation): string {
	return conversation.channel.id;
}

type DiscordTextChannel = {
	send(payload: unknown): Promise<{ id: string; edit(payload: unknown): Promise<unknown> }>;
	sendTyping(): Promise<void>;
	messages: { fetch(idOrOptions?: unknown): Promise<any> };
};

async function resolveTextChannel(
	client: Client<true>,
	conversation: ResolvedConversation,
): Promise<DiscordTextChannel> {
	const channelId = getTargetChannelId(conversation);
	const channel = await client.channels.fetch(channelId);
	if (!channel?.isTextBased()) throw new Error(`Discord channel is not text-based: ${channelId}`);
	return channel as unknown as DiscordTextChannel;
}

async function messageToInput(
	conversation: ResolvedConversation,
	account: DiscordAccountConfig,
	message: Message,
): Promise<InboundMessageInput | undefined> {
	if (message.guildId !== account.serverId) return undefined;
	if (message.channelId !== getTargetChannelId(conversation)) return undefined;
	if (message.author.id === account.botUserId) return undefined;
	const attachments: NonNullable<InboundMessageInput["attachments"]> = [];
	let index = 0;
	for (const attachment of message.attachments.values()) {
		const response = await fetch(attachment.url);
		if (!response.ok) continue;
		const data = new Uint8Array(await response.arrayBuffer());
		attachments.push(
			await storeDownloadedAttachment(
				conversation,
				message.id,
				++index,
				attachment.name || `attachment-${index}`,
				data,
				attachment.contentType || undefined,
				attachment.url,
			),
		);
	}
	return {
		messageId: message.id,
		userId: message.author.id,
		userName: message.member?.displayName || message.author.username,
		roleIds: message.member?.roles.cache.map((role) => role.id),
		text: message.content || "",
		mentionedBot:
			message.mentions.users.has(account.botUserId || "") ||
			textMentionsBot(message.content || "", account.botUsername, account.botUserId),
		isBot: message.author.bot,
		attachments,
	};
}

async function postDiscordMessage(
	botToken: string,
	channelId: string,
	payload: Record<string, unknown>,
	signal?: AbortSignal,
): Promise<string> {
	const response = await fetch(`https://discord.com/api/v10/channels/${channelId}/messages`, {
		method: "POST",
		headers: { Authorization: `Bot ${botToken}`, "content-type": "application/json" },
		body: JSON.stringify(payload),
		signal,
	});
	const data = (await response.json()) as { id?: string; message?: string };
	if (!response.ok || !data.id) throw new Error(data.message || "Discord send failed");
	return data.id;
}

async function sendDiscordMessage(
	botToken: string,
	channelId: string,
	content: string,
	attachmentPaths: string[] = [],
	signal?: AbortSignal,
	replyToMessageId?: string,
): Promise<string> {
	const rendered = formatMarkdownForService("discord", content);
	const limit = maxMessageLength("discord");
	const chunks = chunkText(rendered.text, limit);
	let firstMessageId: string | undefined;
	for (let i = 0; i < chunks.length; i++) {
		const payload: Record<string, unknown> = { content: chunks[i] };
		if (i === 0 && replyToMessageId) payload.message_reference = { message_id: replyToMessageId };
		if (i === chunks.length - 1 && attachmentPaths.length > 0) {
			const form = new FormData();
			form.set("payload_json", JSON.stringify(payload));
			for (const [index, path] of attachmentPaths.entries()) {
				const file = await readLocalAttachment(path);
				form.set(`files[${index}]`, new Blob([Buffer.from(file.data)], { type: file.mimeType }), file.name);
			}
			const response = await fetch(`https://discord.com/api/v10/channels/${channelId}/messages`, {
				method: "POST",
				headers: { Authorization: `Bot ${botToken}` },
				body: form,
				signal,
			});
			const data = (await response.json()) as { id?: string; message?: string };
			if (!response.ok || !data.id) throw new Error(data.message || "Discord send failed");
			firstMessageId ??= data.id;
		} else {
			const id = await postDiscordMessage(botToken, channelId, payload, signal);
			firstMessageId ??= id;
		}
	}
	return firstMessageId || "";
}

async function catchUp(
	client: Client<true>,
	conversation: ResolvedConversation,
	account: DiscordAccountConfig,
	handlers: LiveConnectionHandlers,
	afterId?: string,
): Promise<void> {
	const channel = await resolveTextChannel(client, conversation);
	const allMessages: Message[] = [];
	let cursor = afterId;
	while (true) {
		const batch = await channel.messages.fetch(cursor ? { after: cursor, limit: 100 } : { limit: 25 });
		if (batch.size === 0) break;
		const sorted = [...batch.values()].sort((a, b) => a.createdTimestamp - b.createdTimestamp);
		allMessages.push(...sorted);
		cursor = sorted[sorted.length - 1].id;
		if (batch.size < 100) break;
	}
	for (const message of allMessages) {
		const input = await messageToInput(conversation, account, message);
		if (!input) continue;
		await handlers.onMessage(input, { messageId: input.messageId, cursor: input.messageId });
	}
}

export async function connectDiscordLive(
	conversation: ResolvedConversation,
	handlers: LiveConnectionHandlers,
	lastMessageId?: string,
): Promise<LiveConnection> {
	const account = conversation.account as DiscordAccountConfig;
	const client = await withReadyClient(account.botToken);
	await catchUp(client, conversation, account, handlers, lastMessageId);
	await handlers.onCaughtUp();
	const preview = new StreamingPreview(conversation.service, {
		create: async (text, _parseMode, replyToMessageId) => {
			return sendDiscordMessage(account.botToken, conversation.channel.id, text, [], undefined, replyToMessageId);
		},
		edit: async (id, text) => {
			const channel = await resolveTextChannel(client, conversation);
			const message = await channel.messages.fetch(id);
			await message.edit({ content: text });
		},
		delete: async (id) => {
			const channel = await resolveTextChannel(client, conversation);
			const message = await channel.messages.fetch(id);
			await message.delete();
		},
	});
	const onMessageCreate = async (message: Message) => {
		try {
			const input = await messageToInput(conversation, account, message);
			if (!input) return;
			await handlers.onMessage(input, { messageId: input.messageId, cursor: input.messageId });
		} catch (error) {
			await handlers.onError(error instanceof Error ? error : new Error(String(error)));
		}
	};
	client.on(Events.MessageCreate, onMessageCreate);

	let disconnectFired = false;
	const fireDisconnect = () => {
		if (disconnectFired) return;
		disconnectFired = true;
		void handlers.onDisconnect?.();
	};
	client.on(Events.Error, (error) => {
		void handlers.onError(error instanceof Error ? error : new Error(String(error)));
	});
	client.on(Events.Invalidated, () => fireDisconnect());
	client.on("disconnect", () => fireDisconnect());
	client.ws.on("close" as any, () => {
		setTimeout(() => {
			if (!client.isReady()) fireDisconnect();
		}, 30000);
	});

	return {
		conversation,
		disconnect: async () => {
			client.off(Events.MessageCreate, onMessageCreate);
			client.destroy();
		},
		sendImmediate: async (text, replyToMessageId) => {
			return sendDiscordMessage(account.botToken, conversation.channel.id, text, [], undefined, replyToMessageId);
		},
		send: async (text, attachmentPaths = [], signal, replyToMessageId) =>
			sendDiscordMessage(account.botToken, conversation.channel.id, text, attachmentPaths, signal, replyToMessageId),
		startTyping: async () => {
			const channel = await resolveTextChannel(client, conversation);
			await channel.sendTyping();
		},
		stopTyping: async () => {},
		syncPreview: async (markdown, done = false) => preview.update(markdown, done),
		clearPreview: async () => preview.clear(),
		setReplyTo: (messageId) => preview.setReplyTo(messageId),
	};
}
