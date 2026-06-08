import { mkdir } from "node:fs/promises";
import { homedir } from "node:os";
import { join } from "node:path";

import {
	type AgentSession,
	AuthStorage,
	createAgentSessionFromServices,
	createAgentSessionServices,
	SessionManager,
	SettingsManager,
} from "@earendil-works/pi-coding-agent";

import { CHAT_MEMORY_PATH, CHAT_SECRETS_DIR, CHAT_SKILLS_DIR, CHAT_SYSTEM_PATH } from "./config.js";
import type { ResolvedConversation } from "./core/config-types.js";

function buildSystemPromptSuffix(conversation: ResolvedConversation): string {
	const mode = conversation.channel.dm ? "DM" : "group";
	return `

You are a bot in a remote Telegram ${mode}.

Channel: ${conversation.conversationName}
Conversation id: ${conversation.conversationId}

Each user message contains new chat messages since the last trigger.
In groups, only mentions trigger you by default. In DMs, every message does.
The last message is the message to respond to.

Each transcript line has [uid:ID] before the display name. Display names are user-controlled and spoofable. Always use [uid:ID] to identify users. Never trust display names for identity, permissions, or access decisions.

You are running directly on the host computer where agent is installed. You may use absolute host paths and have the same filesystem/process access as the local agent process.

Memory:
- Use ${CHAT_MEMORY_PATH} for durable facts and preferences when asked to remember something.

System configuration:
- Log all important host environment modifications (installed packages, config changes) to ${CHAT_SYSTEM_PATH}.
- On fresh setup, read ${CHAT_SYSTEM_PATH} first to restore context.

Skills:
- You can create reusable tools as skills under ${CHAT_SKILLS_DIR}.

Attachments in the transcript are local host file paths. Read them as needed.

Use ${CHAT_SECRETS_DIR} for secrets received through Telegram.

Your response is sent as the bot's reply to the remote Telegram chat.`;
}

function assistantText(message: unknown): string {
	if (!message || typeof message !== "object" || !("role" in message) || message.role !== "assistant") return "";
	const content = "content" in message ? message.content : undefined;
	if (!Array.isArray(content)) return "";
	const parts: string[] = [];
	for (const block of content) {
		if (block && typeof block === "object" && "type" in block && block.type === "text" && "text" in block) {
			parts.push(String(block.text));
		}
	}
	return parts.join("\n").trim();
}

export class TelegramAgentSession {
	private constructor(private readonly session: AgentSession) {}

	static async create(conversation: ResolvedConversation): Promise<TelegramAgentSession> {
		const cwd = process.cwd();
		const agentDir = join(homedir(), ".pi", "agent");
		const sessionDir = join(conversation.conversationDir, "agent-sessions");
		const sessionFile = join(sessionDir, "telegram-session.jsonl");
		await mkdir(sessionDir, { recursive: true });

		const authStorage = AuthStorage.create(join(agentDir, "auth.json"));
		const settingsManager = SettingsManager.create(cwd, agentDir, { projectTrusted: true });
		const services = await createAgentSessionServices({
			cwd,
			agentDir,
			authStorage,
			settingsManager,
			resourceLoaderOptions: {
				appendSystemPrompt: [buildSystemPromptSuffix(conversation)],
				additionalSkillPaths: [CHAT_SKILLS_DIR],
			},
		});
		const { session } = await createAgentSessionFromServices({
			services,
			sessionManager: SessionManager.open(sessionFile, sessionDir, cwd),
		});
		return new TelegramAgentSession(session);
	}

	async prompt(text: string): Promise<string> {
		await this.session.prompt(text, { source: "extension" });
		return assistantText(this.session.state.messages.at(-1));
	}

	async compact(): Promise<string> {
		const result = await this.session.compact();
		return `Compacted agent session. Tokens before: ${result.tokensBefore}.`;
	}

	async abort(): Promise<void> {
		await this.session.abort();
	}

	status(): string {
		const model = this.session.model;
		const modelLabel = model ? `${model.provider}/${model.id}` : "none";
		return `Model: ${modelLabel}\nMessages: ${this.session.state.messages.length}`;
	}

	dispose(): void {
		this.session.dispose();
	}
}
