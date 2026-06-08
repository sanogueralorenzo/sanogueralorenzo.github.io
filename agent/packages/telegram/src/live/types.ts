import type { ResolvedConversation } from "../core/config-types.js";
import type { InboundMessageInput } from "../core/runtime-types.js";

export interface LiveConnectionHandlers {
	onMessage(input: InboundMessageInput, checkpoint?: { cursor?: string; messageId?: string }): Promise<void>;
	onCaughtUp(): Promise<void>;
	onError(error: Error): Promise<void>;
	onDisconnect?(): Promise<void>;
}

export interface ResumeState {
	cursor?: string;
	messageId?: string;
}

export interface LiveConnection {
	conversation: ResolvedConversation;
	disconnect(): Promise<void>;
	sendImmediate(text: string, replyToMessageId?: string): Promise<string | undefined>;
	send(
		text: string,
		attachmentPaths?: string[],
		signal?: AbortSignal,
		replyToMessageId?: string,
	): Promise<string | undefined>;
	startTyping(status?: string): Promise<void>;
	stopTyping(): Promise<void>;
	syncPreview(markdown: string, done?: boolean): Promise<string[]>;
	clearPreview(): Promise<void>;
	setReplyTo(messageId: string | undefined): void;
}
