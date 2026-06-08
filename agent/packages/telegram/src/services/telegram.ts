import type { TelegramAccountConfig } from "../core/config-types.js";
import type { AccountValidationResult, DiscoverySnapshot } from "../core/discovery-types.js";
import type { AccountDraft, DiscoveryProvider } from "./types.js";

interface TelegramResponse<T> {
	ok: boolean;
	result?: T;
	description?: string;
}

interface TelegramUser {
	id: number;
	username?: string;
	first_name: string;
	last_name?: string;
}

async function callTelegram<T>(botToken: string, method: string): Promise<T> {
	const response = await fetch(`https://api.telegram.org/bot${botToken}/${method}`);
	const data = (await response.json()) as TelegramResponse<T>;
	if (!response.ok || !data.ok || data.result === undefined) {
		throw new Error(data.description || `Telegram API ${method} failed`);
	}
	return data.result;
}

export const telegramDiscoveryProvider: DiscoveryProvider = {
	service: "telegram",
	async validate(draft: AccountDraft): Promise<AccountValidationResult> {
		const user = await callTelegram<TelegramUser>(draft.botToken, "getMe");
		const fullName = [user.first_name, user.last_name].filter(Boolean).join(" ") || user.username || String(user.id);
		return {
			identity: {
				id: String(user.id),
				name: fullName,
				userName: user.username,
			},
			warnings: [
				"Telegram bots cannot enumerate chats or users up front. Use the guided Add DM/Add group flow after account creation.",
			],
		};
	},
	async fetchSnapshot(accountId: string, account: TelegramAccountConfig): Promise<DiscoverySnapshot> {
		const validation = await this.validate({ service: "telegram", botToken: account.botToken, name: account.name });
		return {
			accountId,
			service: "telegram",
			fetchedAt: new Date().toISOString(),
			identity: validation.identity,
			channels: [],
			users: [],
			roles: [],
			warnings: validation.warnings,
			capabilities: {
				canListChannels: false,
				canListUsers: false,
				canListRoles: false,
			},
		};
	},
};
