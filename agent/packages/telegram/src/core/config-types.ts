export type ChatService = "telegram";

export type TriggerMode = "message";

export interface AccessPolicy {
	trigger?: TriggerMode;
	ignoreBots?: boolean;
	allowedUserIds?: string[];
	allowedRoleIds?: string[];
}

export interface ConfiguredChannel {
	id: string;
	name?: string;
	dm?: boolean;
	access?: AccessPolicy;
}

export interface BaseAccountConfig {
	service: ChatService;
	name?: string;
	access?: AccessPolicy;
	channels: Record<string, ConfiguredChannel>;
}

export interface TelegramAccountConfig extends BaseAccountConfig {
	service: "telegram";
	botToken: string;
	botUsername?: string;
	botUserId?: string;
}

export type ChatAccountConfig = TelegramAccountConfig;

export interface ChatConfig {
	botName?: string;
	accounts: Record<string, ChatAccountConfig>;
}

export interface ResolvedConversation {
	service: ChatService;
	botName: string;
	accountId: string;
	account: ChatAccountConfig;
	channelKey: string;
	channel: ConfiguredChannel;
	conversationId: string;
	conversationName: string;
	access: AccessPolicy;
	accountDir: string;
	conversationDir: string;
	channelDataDir: string;
	logPath: string;
	filesDir: string;
	lockPath: string;
}
