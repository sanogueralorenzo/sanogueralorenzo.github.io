import type {
	ChatAccountConfig,
	ChatService,
	DiscordAccountConfig,
	TelegramAccountConfig,
} from "../core/config-types.js";
import type { DiscoverySnapshot } from "../core/discovery-types.js";
import { removeDiscoverySnapshot, saveDiscoverySnapshot } from "../discovery-store.js";
import { discordDiscoveryProvider } from "./discord.js";
import { telegramDiscoveryProvider } from "./telegram.js";
import type { AccountDraft, DiscoveryProvider } from "./types.js";

const providers: Record<ChatService, DiscoveryProvider> = {
	telegram: telegramDiscoveryProvider,
	discord: discordDiscoveryProvider,
};

export async function validateAccountDraft(draft: AccountDraft) {
	return providers[draft.service].validate(draft);
}

export async function refreshAccountSnapshot(
	accountId: string,
	account: ChatAccountConfig,
): Promise<DiscoverySnapshot> {
	await removeDiscoverySnapshot(accountId);
	const snapshot = await providers[account.service].fetchSnapshot(accountId, account);
	await saveDiscoverySnapshot(snapshot);
	return snapshot;
}

export function updateAccountIdentityFromSnapshot(
	account: ChatAccountConfig,
	snapshot: DiscoverySnapshot,
): ChatAccountConfig {
	if (account.service === "telegram") {
		const next: TelegramAccountConfig = {
			...account,
			botUserId: snapshot.identity.id,
			botUsername: snapshot.identity.userName,
		};
		if (!next.name) next.name = snapshot.identity.name;
		return next;
	}
	const next: DiscordAccountConfig = {
		...account,
		botUserId: snapshot.identity.id,
		botUsername: snapshot.identity.userName,
		serverId: account.serverId,
		serverName: snapshot.identity.workspaceName || account.serverName,
	};
	if (!next.name) next.name = snapshot.identity.name;
	return next;
}
