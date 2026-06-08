import type { ChatAccountConfig, ChatService } from "../core/config-types.js";
import type { AccountValidationResult, DiscoverySnapshot } from "../core/discovery-types.js";

export interface AccountDraft {
	service: ChatService;
	botToken: string;
	name?: string;
}

export interface DiscoveryProvider {
	service: ChatService;
	validate(draft: AccountDraft): Promise<AccountValidationResult>;
	fetchSnapshot(accountId: string, account: ChatAccountConfig): Promise<DiscoverySnapshot>;
}
