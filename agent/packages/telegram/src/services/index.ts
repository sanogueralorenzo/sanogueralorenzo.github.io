import type { ChatAccountConfig, ChatService, TelegramAccountConfig } from "../core/config-types.js";
import type { DiscoverySnapshot } from "../core/discovery-types.js";
import { removeDiscoverySnapshot, saveDiscoverySnapshot } from "../discovery-store.js";
import { telegramDiscoveryProvider } from "./telegram.js";
import type { AccountDraft, DiscoveryProvider } from "./types.js";

const providers: Record<ChatService, DiscoveryProvider> = {
	telegram: telegramDiscoveryProvider,
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
	const next: TelegramAccountConfig = {
		...account,
		botUserId: snapshot.identity.id,
		botUsername: snapshot.identity.userName,
	};
	if (!next.name) next.name = snapshot.identity.name;
	return next;
}
