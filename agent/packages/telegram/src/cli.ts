#!/usr/bin/env node
import { spawn, spawnSync } from "node:child_process";
import { mkdir, readFile, writeFile } from "node:fs/promises";
import { homedir } from "node:os";
import { dirname, join } from "node:path";
import { createInterface } from "node:readline/promises";
import { fileURLToPath } from "node:url";

import { CHAT_HOME, ensureChatHome, listConfiguredConversations, loadChatConfig, saveChatConfig } from "./config.js";
import type { AccessPolicy, ChatConfig, ConfiguredChannel, TelegramAccountConfig } from "./core/config-types.js";
import { makeAccountKey, makeChannelKey } from "./core/keys.js";
import { refreshAccountSnapshot, updateAccountIdentityFromSnapshot, validateAccountDraft } from "./services/index.js";

interface TelegramApiResponse<T> {
	ok: boolean;
	result?: T;
	description?: string;
}

interface TelegramUser {
	id: number;
	username?: string;
	first_name?: string;
	last_name?: string;
	is_bot?: boolean;
}

interface TelegramChat {
	id: number;
	type: string;
	title?: string;
	username?: string;
	first_name?: string;
	last_name?: string;
}

interface TelegramMessage {
	message_id: number;
	chat: TelegramChat;
	from?: TelegramUser;
	text?: string;
	caption?: string;
}

interface TelegramUpdate {
	update_id: number;
	message?: TelegramMessage;
	edited_message?: TelegramMessage;
}

interface ObservedTelegramTarget {
	chatId: string;
	chatName: string;
	userId?: string;
	userName?: string;
	dm: boolean;
}

const packageDir = dirname(dirname(fileURLToPath(import.meta.url)));
const servicePath = join(homedir(), ".config", "systemd", "user", "agent-telegram.service");
const workerPrefix = "agent-telegram-";

function usage(): string {
	return `agent telegram <command>

Commands:
  login                         Configure a Telegram bot and trusted DM/group
  start [conversation]          Start Telegram agent worker in tmux
  start --foreground [conv]     Run Telegram agent worker in the foreground
  stop [conversation]           Stop Telegram agent worker(s)
  status                        Show Telegram config and worker state
  autostart enable [conv]       Enable Telegram worker on boot/login
  autostart disable             Disable Telegram worker autostart
  autostart status              Show autostart state
  doctor                        Check required local tools
`;
}

function normalizeArgs(argv: string[]): string[] {
	return argv[0] === "telegram" ? argv.slice(1) : argv;
}

function shellQuote(value: string): string {
	return `'${value.replace(/'/g, `'"'"'`)}'`;
}

function safeName(value: string): string {
	return (
		value
			.replace(/[^a-zA-Z0-9_.-]+/g, "-")
			.replace(/^-+|-+$/g, "")
			.slice(0, 80) || "default"
	);
}

function tmuxName(conversationId: string): string {
	return `${workerPrefix}${safeName(conversationId)}`;
}

function ensureUniqueKey(existing: Record<string, unknown>, base: string): string {
	if (!existing[base]) return base;
	let index = 2;
	while (existing[`${base}-${index}`]) index += 1;
	return `${base}-${index}`;
}

function displayName(user: TelegramUser | undefined): string | undefined {
	if (!user) return undefined;
	return user.username || [user.first_name, user.last_name].filter(Boolean).join(" ") || String(user.id);
}

function chatDisplayName(chat: TelegramChat): string {
	return chat.title || chat.username || [chat.first_name, chat.last_name].filter(Boolean).join(" ") || String(chat.id);
}

async function callTelegram<T>(botToken: string, method: string, body: Record<string, unknown>): Promise<T> {
	const response = await fetch(`https://api.telegram.org/bot${botToken}/${method}`, {
		method: "POST",
		headers: { "content-type": "application/json" },
		body: JSON.stringify(body),
	});
	const data = (await response.json()) as TelegramApiResponse<T>;
	if (!response.ok || !data.ok || data.result === undefined)
		throw new Error(data.description || `Telegram API ${method} failed`);
	return data.result;
}

async function prompt(label: string, fallback = ""): Promise<string> {
	const rl = createInterface({ input: process.stdin, output: process.stdout });
	try {
		const suffix = fallback ? ` (${fallback})` : "";
		const value = await rl.question(`${label}${suffix}: `);
		return value.trim() || fallback;
	} finally {
		rl.close();
	}
}

async function getLatestUpdateId(botToken: string): Promise<number | undefined> {
	const updates = await callTelegram<TelegramUpdate[]>(botToken, "getUpdates", { offset: -1, limit: 1, timeout: 0 });
	return updates.at(-1)?.update_id;
}

function matchObservedTarget(message: TelegramMessage | undefined): ObservedTelegramTarget | undefined {
	if (!message) return undefined;
	const dm = message.chat.type === "private";
	if (!dm && message.chat.type !== "group" && message.chat.type !== "supergroup") return undefined;
	return {
		chatId: String(message.chat.id),
		chatName: chatDisplayName(message.chat),
		userId: message.from ? String(message.from.id) : undefined,
		userName: displayName(message.from),
		dm,
	};
}

async function observeTelegramTarget(botToken: string, botUsername?: string): Promise<ObservedTelegramTarget> {
	await callTelegram(botToken, "deleteWebhook", { drop_pending_updates: false });
	let offset = (await getLatestUpdateId(botToken)) ?? 0;
	console.log("");
	if (botUsername) {
		console.log(`Open Telegram and message @${botUsername}.`);
		console.log(`Telegram Web: https://web.telegram.org/k/#@${botUsername}`);
	} else {
		console.log("Open Telegram and send a message to your bot.");
	}
	console.log("Waiting for the next DM/group message... Press Ctrl+C to cancel.\n");
	while (true) {
		const updates = await callTelegram<TelegramUpdate[]>(botToken, "getUpdates", {
			offset: offset + 1,
			timeout: 30,
			allowed_updates: ["message", "edited_message"],
		});
		for (const update of updates) {
			offset = update.update_id;
			const observed = matchObservedTarget(update.message || update.edited_message);
			if (observed) return observed;
		}
	}
}

async function commandLogin(): Promise<void> {
	await ensureChatHome();
	const config = await loadChatConfig();
	const token = await prompt("Telegram bot token");
	if (!token) throw new Error("Telegram bot token is required");
	const validation = await validateAccountDraft({ service: "telegram", botToken: token });
	const defaultLabel = validation.identity.userName || validation.identity.name || "telegram";
	const label = await prompt("Account label", defaultLabel);
	const accountKey = ensureUniqueKey(config.accounts, makeAccountKey("telegram", label));
	let account: TelegramAccountConfig = {
		service: "telegram",
		name: label,
		botToken: token,
		channels: {},
		access: { ignoreBots: true },
	};
	const snapshot = await refreshAccountSnapshot(accountKey, account);
	account = updateAccountIdentityFromSnapshot(account, snapshot) as TelegramAccountConfig;
	const observed = await observeTelegramTarget(account.botToken, account.botUsername);
	const access: AccessPolicy = {
		trigger: observed.dm ? "message" : "mention",
		ignoreBots: true,
		allowedUserIds: observed.userId ? [observed.userId] : undefined,
	};
	const channelKey = ensureUniqueKey(
		account.channels,
		makeChannelKey(observed.dm ? `dm-${observed.userName || observed.chatName}` : observed.chatName, observed.chatId),
	);
	const channel: ConfiguredChannel = {
		id: observed.chatId,
		name: observed.chatName,
		dm: observed.dm,
		access,
	};
	account.channels[channelKey] = channel;
	config.accounts[accountKey] = account;
	await saveChatConfig(config);
	console.log("\nTelegram ready.");
	console.log(`  account: ${accountKey}`);
	console.log(`  chat: ${channelKey}`);
	console.log(`  conversation: ${accountKey}/${channelKey}`);
	console.log("\nStart it with:");
	console.log(`  agent telegram start ${accountKey}/${channelKey}`);
}

function requireTmux(): void {
	const result = spawnSync("tmux", ["-V"], { encoding: "utf8" });
	if (result.error || result.status !== 0) throw new Error("tmux not found. Install tmux and try again.");
}

function tmuxSessionExists(name: string): boolean {
	return spawnSync("tmux", ["has-session", "-t", name], { stdio: "ignore" }).status === 0;
}

function listTmuxSessions(): Set<string> {
	const result = spawnSync("tmux", ["list-sessions", "-F", "#S"], { encoding: "utf8" });
	if (result.error || result.status !== 0) return new Set();
	return new Set(result.stdout.split(/\r?\n/).filter(Boolean));
}

async function resolveConversationId(config: ChatConfig, requested?: string): Promise<string> {
	const conversations = listConfiguredConversations(config);
	if (requested) {
		if (!conversations.some((item) => item.conversationId === requested))
			throw new Error(`Unknown conversation: ${requested}`);
		return requested;
	}
	if (conversations.length === 0) throw new Error("No Telegram chats configured. Run: agent telegram login");
	if (conversations.length === 1) return conversations[0].conversationId;
	throw new Error(
		`Multiple Telegram chats configured. Specify one:\n${conversations.map((item) => `  ${item.conversationId}`).join("\n")}`,
	);
}

async function commandStart(args: string[]): Promise<void> {
	const foreground = args.includes("--foreground");
	const requested = args.find((arg) => arg !== "--foreground");
	const config = await loadChatConfig();
	const conversationId = await resolveConversationId(config, requested);
	if (foreground) {
		await runPiForeground(conversationId);
		return;
	}
	requireTmux();
	const name = tmuxName(conversationId);
	if (tmuxSessionExists(name)) {
		console.log(`Already running: ${name}`);
		return;
	}
	const command = `exec pi -e ${shellQuote(packageDir)} --chat-conversation ${shellQuote(conversationId)}`;
	const result = spawnSync("tmux", ["new-session", "-d", "-s", name, "-c", process.cwd(), command], {
		encoding: "utf8",
	});
	if (result.error || result.status !== 0)
		throw new Error(result.stderr.trim() || result.error?.message || "tmux failed");
	console.log(`Started ${conversationId} (${name})`);
}

async function runPiForeground(conversationId: string): Promise<void> {
	await new Promise<void>((resolve, reject) => {
		const child = spawn("pi", ["-e", packageDir, "--chat-conversation", conversationId], { stdio: "inherit" });
		child.on("error", reject);
		child.on("exit", (code, signal) => {
			if (code === 0) resolve();
			else reject(new Error(`pi exited with ${code ?? signal ?? "unknown"}`));
		});
	});
}

async function commandStop(requested?: string): Promise<void> {
	requireTmux();
	if (requested) {
		const name = tmuxName(requested);
		spawnSync("tmux", ["kill-session", "-t", name], { stdio: "ignore" });
		console.log(`Stopped ${name}`);
		return;
	}
	const sessions = [...listTmuxSessions()].filter((name) => name.startsWith(workerPrefix));
	for (const session of sessions) spawnSync("tmux", ["kill-session", "-t", session], { stdio: "ignore" });
	console.log(sessions.length ? `Stopped ${sessions.length} worker(s).` : "No Telegram workers running.");
}

async function commandStatus(): Promise<void> {
	const config = await loadChatConfig();
	const conversations = listConfiguredConversations(config);
	const sessions = listTmuxSessions();
	console.log(`Config: ${CHAT_HOME}`);
	console.log(`Chats: ${conversations.length}`);
	for (const conversation of conversations) {
		const name = tmuxName(conversation.conversationId);
		console.log(`${sessions.has(name) ? "●" : "○"} ${conversation.conversationId} — ${conversation.conversationName}`);
	}
	await commandAutostartStatus();
}

async function commandAutostartEnable(requested?: string): Promise<void> {
	const config = await loadChatConfig();
	const conversationId = await resolveConversationId(config, requested);
	await mkdir(dirname(servicePath), { recursive: true });
	const cliPath = fileURLToPath(import.meta.url);
	const content = `[Unit]\nDescription=Agent Telegram bridge\nAfter=network-online.target\nWants=network-online.target\n\n[Service]\nType=simple\nWorkingDirectory=${process.cwd()}\nExecStart=/usr/bin/env npx tsx ${cliPath} telegram start --foreground ${conversationId}\nRestart=always\nRestartSec=5\n\n[Install]\nWantedBy=default.target\n`;
	await writeFile(servicePath, content, "utf8");
	spawnSync("systemctl", ["--user", "daemon-reload"], { stdio: "inherit" });
	spawnSync("systemctl", ["--user", "enable", "--now", "agent-telegram.service"], { stdio: "inherit" });
	spawnSync("loginctl", ["enable-linger", process.env.USER || ""], { stdio: "ignore" });
	console.log(`Autostart enabled for ${conversationId}`);
}

async function commandAutostartDisable(): Promise<void> {
	spawnSync("systemctl", ["--user", "disable", "--now", "agent-telegram.service"], { stdio: "inherit" });
	console.log("Autostart disabled.");
}

async function commandAutostartStatus(): Promise<void> {
	let service = "not installed";
	try {
		await readFile(servicePath, "utf8");
		const enabled = spawnSync("systemctl", ["--user", "is-enabled", "agent-telegram.service"], { encoding: "utf8" });
		const active = spawnSync("systemctl", ["--user", "is-active", "agent-telegram.service"], { encoding: "utf8" });
		service = `${enabled.stdout.trim() || "unknown"}, ${active.stdout.trim() || "inactive"}`;
	} catch {
		// keep default
	}
	console.log(`Autostart: ${service}`);
}

function commandDoctor(): void {
	for (const binary of ["pi", "tmux", "systemctl", "npx"]) {
		const result = spawnSync(binary, [binary === "tmux" ? "-V" : "--version"], { encoding: "utf8" });
		console.log(`${result.error || result.status !== 0 ? "✗" : "✓"} ${binary}`);
	}
}

async function main(): Promise<void> {
	const args = normalizeArgs(process.argv.slice(2));
	const command = args.shift();
	try {
		if (!command || command === "help" || command === "--help" || command === "-h") {
			console.log(usage());
			return;
		}
		if (command === "login") return await commandLogin();
		if (command === "start") return await commandStart(args);
		if (command === "stop") return await commandStop(args[0]);
		if (command === "status") return await commandStatus();
		if (command === "doctor") return commandDoctor();
		if (command === "autostart") {
			const sub = args.shift();
			if (sub === "enable") return await commandAutostartEnable(args[0]);
			if (sub === "disable") return await commandAutostartDisable();
			if (sub === "status") return await commandAutostartStatus();
		}
		throw new Error(`Unknown command: ${command}`);
	} catch (error) {
		console.error(error instanceof Error ? error.message : String(error));
		process.exitCode = 1;
	}
}

void main();
