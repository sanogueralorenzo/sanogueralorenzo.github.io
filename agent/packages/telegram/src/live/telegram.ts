import type { ResolvedConversation, TelegramAccountConfig } from "../core/config-types.js";
import type { InboundMessageInput } from "../core/runtime-types.js";
import { chunkText } from "../render/chunking.js";
import { formatMarkdownForService, maxMessageLength } from "../render/format.js";
import { StreamingPreview } from "../render/streaming.js";
import {
	fetchBinary,
	guessAttachmentKind,
	readLocalAttachment,
	storeDownloadedAttachment,
	textMentionsBot,
} from "./common.js";
import type { LiveConnection, LiveConnectionHandlers, ResumeState } from "./types.js";

interface TelegramResponse<T> {
	ok: boolean;
	result?: T;
	description?: string;
}
interface TelegramUser {
	id: number;
	username?: string;
	is_bot?: boolean;
	first_name?: string;
}
interface TelegramChat {
	id: number;
	type: string;
}
interface TelegramPhotoSize {
	file_id: string;
	file_size?: number;
}
interface TelegramDocument {
	file_id: string;
	file_name?: string;
	mime_type?: string;
}
interface TelegramVideo {
	file_id: string;
	file_name?: string;
	mime_type?: string;
}
interface TelegramAudio {
	file_id: string;
	file_name?: string;
	mime_type?: string;
}
interface TelegramMessage {
	message_id: number;
	media_group_id?: string;
	chat: TelegramChat;
	from?: TelegramUser;
	text?: string;
	caption?: string;
	photo?: TelegramPhotoSize[];
	document?: TelegramDocument;
	video?: TelegramVideo;
	audio?: TelegramAudio;
}
interface TelegramUpdate {
	update_id: number;
	message?: TelegramMessage;
	edited_message?: TelegramMessage;
}
interface TelegramGetFileResult {
	file_path: string;
}

async function callTelegram<T>(
	botToken: string,
	method: string,
	body: Record<string, unknown>,
	options?: { signal?: AbortSignal },
): Promise<T> {
	const response = await fetch(`https://api.telegram.org/bot${botToken}/${method}`, {
		method: "POST",
		headers: { "content-type": "application/json" },
		body: JSON.stringify(body),
		signal: options?.signal,
	});
	const data = (await response.json()) as TelegramResponse<T>;
	if (!response.ok || !data.ok || data.result === undefined)
		throw new Error(data.description || `Telegram API ${method} failed`);
	return data.result;
}

async function downloadTelegramFile(
	conversation: ResolvedConversation,
	botToken: string,
	messageId: string,
	index: number,
	fileId: string,
	fileName: string,
	mimeType?: string,
) {
	const info = await callTelegram<TelegramGetFileResult>(botToken, "getFile", { file_id: fileId });
	const data = await fetchBinary(`https://api.telegram.org/file/bot${botToken}/${info.file_path}`);
	return [await storeDownloadedAttachment(conversation, messageId, index, fileName, data, mimeType, info.file_path)];
}

async function messageToInput(
	conversation: ResolvedConversation,
	account: TelegramAccountConfig,
	message: TelegramMessage,
) {
	if (String(message.chat.id) !== conversation.channel.id) return undefined;
	if (account.botUserId && String(message.from?.id ?? "") === account.botUserId) return undefined;
	const text = (message.text || message.caption || "").trim();
	const attachments: NonNullable<InboundMessageInput["attachments"]> = [];
	const remoteMessageId = String(message.message_id);
	if (message.photo?.length) {
		const largest = [...message.photo].sort((a, b) => (a.file_size ?? 0) - (b.file_size ?? 0)).pop();
		if (largest)
			attachments.push(
				...(await downloadTelegramFile(
					conversation,
					account.botToken,
					remoteMessageId,
					1,
					largest.file_id,
					`photo-${remoteMessageId}.jpg`,
					"image/jpeg",
				)),
			);
	}
	if (message.document)
		attachments.push(
			...(await downloadTelegramFile(
				conversation,
				account.botToken,
				remoteMessageId,
				2,
				message.document.file_id,
				message.document.file_name || `document-${remoteMessageId}`,
				message.document.mime_type,
			)),
		);
	if (message.video)
		attachments.push(
			...(await downloadTelegramFile(
				conversation,
				account.botToken,
				remoteMessageId,
				3,
				message.video.file_id,
				message.video.file_name || `video-${remoteMessageId}.mp4`,
				message.video.mime_type,
			)),
		);
	if (message.audio)
		attachments.push(
			...(await downloadTelegramFile(
				conversation,
				account.botToken,
				remoteMessageId,
				4,
				message.audio.file_id,
				message.audio.file_name || `audio-${remoteMessageId}.mp3`,
				message.audio.mime_type,
			)),
		);
	return {
		messageId: remoteMessageId,
		userId: String(message.from?.id ?? message.chat.id),
		userName: message.from?.username || message.from?.first_name,
		text,
		mentionedBot: textMentionsBot(text, account.botUsername),
		isBot: message.from?.is_bot ?? false,
		attachments,
	};
}

export async function connectTelegramLive(
	conversation: ResolvedConversation,
	handlers: LiveConnectionHandlers,
	resumeState?: ResumeState,
): Promise<LiveConnection> {
	const account = conversation.account as TelegramAccountConfig;
	let abort = false;
	let offset = resumeState?.cursor ? Number(resumeState.cursor) + 1 : 0;
	const pollController = new AbortController();
	const preview = new StreamingPreview(conversation.service, {
		create: async (text, parseMode, replyToMessageId) =>
			String(
				(
					await callTelegram<{ message_id: number }>(account.botToken, "sendMessage", {
						chat_id: Number(conversation.channel.id),
						text,
						parse_mode: parseMode,
						reply_to_message_id: replyToMessageId ? Number(replyToMessageId) : undefined,
					})
				).message_id,
			),
		edit: async (id, text, parseMode) => {
			try {
				await callTelegram(account.botToken, "editMessageText", {
					chat_id: Number(conversation.channel.id),
					message_id: Number(id),
					text,
					parse_mode: parseMode,
				});
			} catch (error) {
				const message = error instanceof Error ? error.message : String(error);
				if (!message.toLowerCase().includes("message is not modified")) throw error;
			}
		},
		delete: async (id) => {
			await callTelegram(account.botToken, "deleteMessage", {
				chat_id: Number(conversation.channel.id),
				message_id: Number(id),
			});
		},
	});
	const mediaGroups = new Map<string, { updates: TelegramUpdate[]; timer?: ReturnType<typeof setTimeout> }>();
	const mergeMediaGroup = (updates: TelegramUpdate[]): TelegramMessage | undefined => {
		const messages = updates
			.map((update) => update.message || update.edited_message)
			.filter(Boolean) as TelegramMessage[];
		if (messages.length === 0) return undefined;
		const merged = { ...messages[0] } as TelegramMessage;
		for (const message of messages.slice(1)) {
			if (!merged.text && message.text) merged.text = message.text;
			if (!merged.caption && message.caption) merged.caption = message.caption;
			if (message.photo?.length) merged.photo = [...(merged.photo ?? []), ...message.photo];
			if (!merged.document && message.document) merged.document = message.document;
			if (!merged.video && message.video) merged.video = message.video;
			if (!merged.audio && message.audio) merged.audio = message.audio;
		}
		return merged;
	};
	const flushMediaGroup = async (key: string): Promise<void> => {
		const state = mediaGroups.get(key);
		mediaGroups.delete(key);
		if (!state) return;
		const merged = mergeMediaGroup(state.updates);
		if (!merged) return;
		const input = await messageToInput(conversation, account, merged);
		if (!input) return;
		const lastUpdateId = state.updates.at(-1)?.update_id;
		await handlers.onMessage(input, {
			cursor: lastUpdateId !== undefined ? String(lastUpdateId) : undefined,
			messageId: input.messageId,
		});
	};
	const processInitialUpdates = async (updates: TelegramUpdate[]): Promise<void> => {
		const grouped = new Map<string, TelegramUpdate[]>();
		for (const update of updates) {
			offset = update.update_id + 1;
			const message = update.message || update.edited_message;
			if (!message) continue;
			if (!message.media_group_id) {
				const input = await messageToInput(conversation, account, message);
				if (input) await handlers.onMessage(input, { cursor: String(update.update_id), messageId: input.messageId });
				continue;
			}
			const key = `${message.chat.id}:${message.media_group_id}`;
			grouped.set(key, [...(grouped.get(key) ?? []), update]);
		}
		for (const updates of grouped.values()) {
			const merged = mergeMediaGroup(updates);
			if (!merged) continue;
			const input = await messageToInput(conversation, account, merged);
			if (!input) continue;
			await handlers.onMessage(input, {
				cursor: String(updates.at(-1)?.update_id ?? 0),
				messageId: input.messageId,
			});
		}
	};
	const initialUpdates = await callTelegram<TelegramUpdate[]>(account.botToken, "getUpdates", {
		offset: offset > 0 ? offset : undefined,
		timeout: 0,
		allowed_updates: ["message", "edited_message"],
	});
	await processInitialUpdates(initialUpdates);
	await handlers.onCaughtUp();
	const loop = (async () => {
		while (!abort) {
			try {
				const updates = await callTelegram<TelegramUpdate[]>(
					account.botToken,
					"getUpdates",
					{ offset: offset > 0 ? offset : undefined, timeout: 30, allowed_updates: ["message", "edited_message"] },
					{ signal: pollController.signal },
				);
				for (const update of updates) {
					offset = update.update_id + 1;
					const message = update.message || update.edited_message;
					if (!message) continue;
					if (message.media_group_id) {
						const key = `${message.chat.id}:${message.media_group_id}`;
						const existing = mediaGroups.get(key) ?? { updates: [] };
						existing.updates.push(update);
						if (existing.timer) clearTimeout(existing.timer);
						existing.timer = setTimeout(() => void flushMediaGroup(key), 1200);
						mediaGroups.set(key, existing);
						continue;
					}
					const input = await messageToInput(conversation, account, message);
					if (input) await handlers.onMessage(input, { cursor: String(update.update_id), messageId: input.messageId });
				}
			} catch (error) {
				if (abort) break;
				if (error instanceof DOMException && error.name === "AbortError") break;
				await handlers.onError(error instanceof Error ? error : new Error(String(error)));
				await new Promise((resolve) => setTimeout(resolve, 3000));
			}
		}
	})();
	return {
		conversation,
		disconnect: async () => {
			abort = true;
			pollController.abort();
			for (const state of mediaGroups.values()) if (state.timer) clearTimeout(state.timer);
			await loop.catch(() => undefined);
		},
		sendImmediate: async (text, replyToMessageId) =>
			String(
				(
					await callTelegram<{ message_id: number }>(account.botToken, "sendMessage", {
						chat_id: Number(conversation.channel.id),
						text,
						reply_to_message_id: replyToMessageId ? Number(replyToMessageId) : undefined,
					})
				).message_id,
			),
		send: async (text, attachmentPaths = [], signal, replyToMessageId) => {
			const rendered = formatMarkdownForService("telegram", text);
			const replyParam = replyToMessageId ? { reply_to_message_id: Number(replyToMessageId) } : {};
			if (attachmentPaths.length === 0) {
				const chunks = chunkText(rendered.text, maxMessageLength("telegram"));
				let firstId: string | undefined;
				for (let i = 0; i < chunks.length; i++) {
					const id = String(
						(
							await callTelegram<{ message_id: number }>(
								account.botToken,
								"sendMessage",
								{
									chat_id: Number(conversation.channel.id),
									text: chunks[i],
									parse_mode: rendered.parseMode,
									...(i === 0 ? replyParam : {}),
								},
								{ signal },
							)
						).message_id,
					);
					firstId ??= id;
				}
				return firstId || "";
			}
			const [firstPath, ...rest] = attachmentPaths;
			const first = await readLocalAttachment(firstPath);
			const firstKind = guessAttachmentKind(first.name, first.mimeType);
			const firstMethod = firstKind === "image" ? "sendPhoto" : "sendDocument";
			const firstField = firstKind === "image" ? "photo" : "document";
			const firstForm = new FormData();
			firstForm.set("chat_id", String(Number(conversation.channel.id)));
			if (replyToMessageId) firstForm.set("reply_to_message_id", String(Number(replyToMessageId)));
			if (text) firstForm.set("caption", text);
			if (text && firstKind === "image") firstForm.set("parse_mode", "Markdown");
			firstForm.set(firstField, new Blob([Buffer.from(first.data)], { type: first.mimeType }), first.name);
			const firstResponse = await fetch(`https://api.telegram.org/bot${account.botToken}/${firstMethod}`, {
				method: "POST",
				body: firstForm,
				signal,
			});
			const firstData = (await firstResponse.json()) as TelegramResponse<{ message_id: number }>;
			if (!firstResponse.ok || !firstData.ok || firstData.result === undefined)
				throw new Error(firstData.description || `${firstMethod} failed`);
			for (const path of rest) {
				const file = await readLocalAttachment(path);
				const kind = guessAttachmentKind(file.name, file.mimeType);
				const method = kind === "image" ? "sendPhoto" : "sendDocument";
				const field = kind === "image" ? "photo" : "document";
				const form = new FormData();
				form.set("chat_id", String(Number(conversation.channel.id)));
				form.set(field, new Blob([Buffer.from(file.data)], { type: file.mimeType }), file.name);
				const response = await fetch(`https://api.telegram.org/bot${account.botToken}/${method}`, {
					method: "POST",
					body: form,
					signal,
				});
				const data = (await response.json()) as TelegramResponse<{ message_id: number }>;
				if (!response.ok || !data.ok || data.result === undefined)
					throw new Error(data.description || `${method} failed`);
			}
			return String(firstData.result.message_id);
		},
		startTyping: async () => {
			await callTelegram(account.botToken, "sendChatAction", {
				chat_id: Number(conversation.channel.id),
				action: "typing",
			});
		},
		stopTyping: async () => {},
		syncPreview: async (markdown, done = false) => preview.update(markdown, done),
		clearPreview: async () => preview.clear(),
		setReplyTo: (messageId) => preview.setReplyTo(messageId),
	};
}
