import type { ChatService } from "./config-types.js";

export interface AccountIdentity {
	id: string;
	name: string;
	userName?: string;
	workspaceId?: string;
	workspaceName?: string;
}

export interface DiscoveredChannel {
	id: string;
	name: string;
	dm?: boolean;
}

export interface DiscoveredUser {
	id: string;
	name: string;
	displayName?: string;
	isBot?: boolean;
}

export interface DiscoveredRole {
	id: string;
	name: string;
}

export interface DiscoverySnapshot {
	accountId: string;
	service: ChatService;
	fetchedAt: string;
	identity: AccountIdentity;
	channels: DiscoveredChannel[];
	users: DiscoveredUser[];
	roles: DiscoveredRole[];
	warnings?: string[];
	capabilities?: {
		canListChannels?: boolean;
		canListUsers?: boolean;
		canListRoles?: boolean;
	};
}

export interface AccountValidationResult {
	identity: AccountIdentity;
	warnings?: string[];
}
