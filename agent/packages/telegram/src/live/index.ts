import type { ResolvedConversation } from "../core/config-types.js";
import { connectTelegramLive } from "./telegram.js";
import type { LiveConnection, LiveConnectionHandlers, ResumeState } from "./types.js";

export async function connectLive(
	conversation: ResolvedConversation,
	handlers: LiveConnectionHandlers,
	resumeState?: ResumeState,
): Promise<LiveConnection> {
	return connectTelegramLive(conversation, handlers, resumeState);
}
