import type { ExtensionContext } from "@mariozechner/pi-coding-agent";
import { BorderedLoader } from "@mariozechner/pi-coding-agent";

import { saveChatConfig } from "../config.js";
import type { AccessPolicy, ChatConfig, ConfiguredChannel, TelegramAccountConfig } from "../core/config-types.js";
import { makeAccountKey, makeChannelKey } from "../core/keys.js";
import { refreshAccountSnapshot, updateAccountIdentityFromSnapshot, validateAccountDraft } from "../services/index.js";
import { runWithLoader, showNotice } from "./dialogs.js";

interface TelegramApiResponse<T> {
	ok: boolean;
	result?: T;
	description?: string;
}

interface TelegramUser {
	id: number;
	username?: string;
	first_name?: string;
	last_name?: string;
}

interface TelegramChat {
	id: number;
	type: string;
	title?: string;
	username?: string;
	first_name?: string;
	last_name?: string;
}

interface TelegramMessage {
	message_id: number;
	chat: TelegramChat;
	from?: TelegramUser;
	text?: string;
	caption?: string;
}

interface TelegramUpdate {
	update_id: number;
	message?: TelegramMessage;
	edited_message?: TelegramMessage;
}

type TelegramSetupMode = "dm" | "group";

interface ObservedTelegramTarget {
	chatId: string;
	chatName: string;
	userId?: string;
	userName?: string;
}

function displayName(user: TelegramUser | undefined): string | undefined {
	if (!user) return undefined;
	return user.username || [user.first_name, user.last_name].filter(Boolean).join(" ") || String(user.id);
}

function chatDisplayName(chat: TelegramChat): string {
	return chat.title || chat.username || [chat.first_name, chat.last_name].filter(Boolean).join(" ") || String(chat.id);
}

function ensureUniqueKey(existing: Record<string, unknown>, base: string): string {
	if (!existing[base]) return base;
	let index = 2;
	while (existing[`${base}-${index}`]) index += 1;
	return `${base}-${index}`;
}

async function callTelegram<T>(botToken: string, method: string, body: Record<string, unknown>): Promise<T> {
	const response = await fetch(`https://api.telegram.org/bot${botToken}/${method}`, {
		method: "POST",
		headers: { "content-type": "application/json" },
		body: JSON.stringify(body),
	});
	const data = (await response.json()) as TelegramApiResponse<T>;
	if (!response.ok || !data.ok || data.result === undefined)
		throw new Error(data.description || `Telegram API ${method} failed`);
	return data.result;
}

async function getLatestUpdateId(botToken: string): Promise<number | undefined> {
	const updates = await callTelegram<TelegramUpdate[]>(botToken, "getUpdates", { offset: -1, limit: 1, timeout: 0 });
	return updates.at(-1)?.update_id;
}

function buildSetupMessage(mode: TelegramSetupMode, botUsername?: string): string {
	const webLink = botUsername ? `https://web.telegram.org/k/#@${botUsername}` : undefined;
	const appLink = botUsername ? `tg://resolve?domain=${botUsername}` : undefined;
	const lines = [mode === "dm" ? "Telegram DM setup" : "Telegram group setup", ""];
	if (botUsername) {
		lines.push(`Bot: @${botUsername}`);
		lines.push(`Open in Telegram Web: ${webLink}`);
		lines.push(`Open on device: ${appLink}`);
		lines.push("");
	}
	if (mode === "dm") lines.push("Open the bot DM and send /start.");
	else {
		lines.push("Add the bot to the target group.");
		lines.push("Then send /start or mention the bot in that group.");
	}
	return lines.join("\n");
}

function matchObservedTarget(message: TelegramMessage, mode: TelegramSetupMode): ObservedTelegramTarget | undefined {
	if (mode === "dm" && message.chat.type !== "private") return undefined;
	if (mode === "group" && message.chat.type !== "group" && message.chat.type !== "supergroup") return undefined;
	return {
		chatId: String(message.chat.id),
		chatName: chatDisplayName(message.chat),
		userId: message.from ? String(message.from.id) : undefined,
		userName: displayName(message.from),
	};
}

async function observeTelegramTarget(
	ctx: ExtensionContext,
	botToken: string,
	botUsername: string | undefined,
	mode: TelegramSetupMode,
): Promise<ObservedTelegramTarget | undefined> {
	const message = buildSetupMessage(mode, botUsername);
	const result = await ctx.ui.custom<ObservedTelegramTarget | undefined>((tui, theme, _kb, done) => {
		const loader = new BorderedLoader(tui, theme, message, { cancellable: true });
		loader.onAbort = () => done(undefined);
		void (async () => {
			try {
				await callTelegram(botToken, "deleteWebhook", { drop_pending_updates: false });
				let offset = (await getLatestUpdateId(botToken)) ?? 0;
				while (!loader.signal.aborted) {
					const updates = await callTelegram<TelegramUpdate[]>(botToken, "getUpdates", {
						offset: offset + 1,
						timeout: 30,
						allowed_updates: ["message", "edited_message"],
					});
					for (const update of updates) {
						offset = update.update_id;
						const observed = matchObservedTarget(
							update.message || update.edited_message || ({} as TelegramMessage),
							mode,
						);
						if (observed) {
							done(observed);
							return;
						}
					}
				}
			} catch {
				done(undefined);
			}
		})();
		return loader;
	});
	return result;
}

export async function createTelegramAccountWithGuidedSetup(
	ctx: ExtensionContext,
	config: ChatConfig,
): Promise<string | undefined> {
	const token = await ctx.ui.input("Telegram bot token", "123456:ABCDEF...");
	if (!token?.trim()) return undefined;
	const validation = await runWithLoader(ctx, "Validating Telegram bot token...", () =>
		validateAccountDraft({ service: "telegram", botToken: token.trim() }),
	);
	if (validation.error) {
		await showNotice(ctx, "Telegram setup error", validation.error, "error");
		return undefined;
	}
	if (!validation.value) return undefined;
	const accountLabel = await ctx.ui.input(
		"Account label",
		validation.value.identity.userName || validation.value.identity.name || "telegram",
	);
	if (accountLabel === undefined) return undefined;
	const baseAccountKey = makeAccountKey(
		"telegram",
		accountLabel.trim() || validation.value.identity.userName || validation.value.identity.name,
	);
	const accountKey = ensureUniqueKey(config.accounts, baseAccountKey);
	let account: TelegramAccountConfig = {
		service: "telegram",
		name: accountLabel.trim() || undefined,
		botToken: token.trim(),
		channels: {},
		access: { ignoreBots: true },
	};
	const snapshot = await runWithLoader(ctx, "Fetching Telegram bot info...", () =>
		refreshAccountSnapshot(accountKey, account),
	);
	if (snapshot.error) {
		await showNotice(ctx, "Telegram setup error", snapshot.error, "error");
		return undefined;
	}
	if (!snapshot.value) return undefined;
	account = updateAccountIdentityFromSnapshot(account, snapshot.value) as TelegramAccountConfig;
	config.accounts[accountKey] = account;
	await saveChatConfig(config);
	await showNotice(ctx, "Telegram account created", `Created ${accountKey}`, "info");
	return accountKey;
}

export async function addTelegramObservedTargetToAccount(
	ctx: ExtensionContext,
	config: ChatConfig,
	accountId: string,
	account: TelegramAccountConfig,
	mode: TelegramSetupMode,
): Promise<string | undefined> {
	const observed = await observeTelegramTarget(ctx, account.botToken, account.botUsername, mode);
	if (!observed) return undefined;
	const channelAccess: AccessPolicy = {
		trigger: mode === "dm" ? "message" : "mention",
		ignoreBots: true,
		allowedUserIds: mode === "dm" && observed.userId ? [observed.userId] : undefined,
	};
	const baseChannelKey = makeChannelKey(
		mode === "dm" ? `dm-${observed.userName || observed.chatName}` : observed.chatName,
		observed.chatId,
	);
	const channelKey = ensureUniqueKey(account.channels, baseChannelKey);
	const channel: ConfiguredChannel = {
		id: observed.chatId,
		name: observed.chatName,
		dm: mode === "dm",
		access: channelAccess,
	};
	account.channels[channelKey] = channel;
	config.accounts[accountId] = account;
	await saveChatConfig(config);
	await showNotice(ctx, "Telegram channel configured", `Configured ${accountId}/${channelKey}`, "info");
	return channelKey;
}
