import { mkdir } from "node:fs/promises";
import { join } from "node:path";
import { TelegramAgentSession } from "./agent-session.js";
import { CHAT_SECRETS_DIR, ensureChatHome, loadChatConfig, resolveConversation } from "./config.js";
import { connectLive } from "./live/index.js";
import type { LiveConnection } from "./live/types.js";
import { ConversationRuntime } from "./runtime.js";
import { tryDecryptSecret } from "./secrets.js";

export async function runTelegramDaemon(conversationId: string): Promise<void> {
	await ensureChatHome();
	await mkdir(CHAT_SECRETS_DIR, { recursive: true });
	const config = await loadChatConfig();
	const resolvedConversation = resolveConversation(config, conversationId);
	if (!resolvedConversation) throw new Error(`Unknown configured Telegram conversation: ${conversationId}`);
	const conversation = resolvedConversation;

	const ownerId = `agent-telegram-${process.pid}-${Date.now()}`;
	const runtime = await ConversationRuntime.connect(conversation, ownerId);
	const agentSession = await TelegramAgentSession.create(conversation);
	let liveConnection: LiveConnection | undefined;
	let activeJob = false;
	let running = false;

	async function dispatch(): Promise<void> {
		if (running) return;
		const next = runtime.beginNextJob();
		if (!next) return;
		running = true;
		activeJob = true;
		liveConnection?.setReplyTo(next.triggerMessageId);
		await liveConnection?.startTyping();
		try {
			const reply = await agentSession.prompt(next.prompt);
			const remoteMessageId = reply
				? await liveConnection?.send(reply, [], undefined, next.triggerMessageId)
				: undefined;
			await runtime.completeActiveJob(reply, remoteMessageId);
		} catch (error) {
			const message = error instanceof Error ? error.message : String(error);
			await runtime.failActiveJob(message);
			await liveConnection?.sendImmediate(`agent-telegram error: ${message}`, next.triggerMessageId);
		} finally {
			await liveConnection?.stopTyping();
			activeJob = false;
			running = false;
			await dispatch();
		}
	}

	liveConnection = await connectLive(
		conversation,
		{
			onMessage: async (input, checkpoint) => {
				const secretResult = tryDecryptSecret(input.text);
				if (secretResult) {
					await mkdir(CHAT_SECRETS_DIR, { recursive: true });
					const secretPath = join(CHAT_SECRETS_DIR, secretResult.name.replace(/[^a-zA-Z0-9._-]+/g, "_"));
					await import("node:fs/promises").then((fs) => fs.writeFile(secretPath, secretResult.decrypted));
					await liveConnection?.sendImmediate(`✅ Secret received and stored as ${secretPath}`);
					if (checkpoint) await runtime.noteCheckpoint(checkpoint);
					return;
				}
				const control = runtime.isArmed() ? runtime.parseControlCommand(input) : undefined;
				if (control === "stop") {
					if (activeJob) {
						await agentSession.abort();
						await liveConnection?.sendImmediate("Aborted current turn.");
					} else await liveConnection?.sendImmediate("No active turn.");
					return;
				}
				if (control === "status") {
					const status = runtime.getStatus();
					await liveConnection?.sendImmediate(
						`Telegram: connected\nChat: ${status.conversationName}\nQueue: ${status.queueLength}${status.hasActiveJob ? " active" : ""}\n${agentSession.status()}`,
					);
					return;
				}
				if (control === "compact") {
					try {
						await liveConnection?.sendImmediate(await agentSession.compact());
					} catch (error) {
						const message = error instanceof Error ? error.message : String(error);
						await liveConnection?.sendImmediate(`Compaction failed: ${message}`);
					}
					return;
				}
				await runtime.ingestInbound(input, checkpoint);
				await dispatch();
			},
			onCaughtUp: async () => runtime.armAfterCurrentTail(),
			onError: async (error) => runtime.appendError(error.message),
			onDisconnect: async () => {
				agentSession.dispose();
				process.exit(1);
			},
		},
		runtime.getLastCheckpoint(),
	);

	console.log(`agent-telegram connected: ${conversation.conversationId}`);
	await dispatch();
	await new Promise(() => undefined);
}
