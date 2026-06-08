import { appendFile, copyFile, lstat, mkdir, open, readFile, unlink, writeFile } from "node:fs/promises";
import { basename, dirname, extname, join, relative, resolve } from "node:path";

import type {
	AttachmentInput,
	AttachmentKind,
	ChatLogRecord,
	InboundMessageInput,
	ResolvedConversation,
	StoredAttachment,
} from "../types.js";

function guessAttachmentKind(path: string): AttachmentKind {
	const ext = extname(path).toLowerCase();
	if ([".png", ".jpg", ".jpeg", ".gif", ".webp"].includes(ext)) return "image";
	if ([".mp3", ".wav", ".ogg", ".m4a"].includes(ext)) return "audio";
	if ([".mp4", ".mov", ".webm"].includes(ext)) return "video";
	return "file";
}

function guessMimeType(path: string): string | undefined {
	const ext = extname(path).toLowerCase();
	if (ext === ".png") return "image/png";
	if (ext === ".jpg" || ext === ".jpeg") return "image/jpeg";
	if (ext === ".gif") return "image/gif";
	if (ext === ".webp") return "image/webp";
	if (ext === ".mp3") return "audio/mpeg";
	if (ext === ".wav") return "audio/wav";
	if (ext === ".ogg") return "audio/ogg";
	if (ext === ".mp4") return "video/mp4";
	if (ext === ".json") return "application/json";
	if (ext === ".md") return "text/markdown";
	if (ext === ".txt" || ext === ".log") return "text/plain";
	return undefined;
}

function sanitizeFileName(value: string): string {
	return value.replace(/[^a-zA-Z0-9._-]+/g, "_");
}

async function ensureRegularFile(path: string): Promise<void> {
	try {
		const info = await lstat(path);
		if (!info.isSymbolicLink()) return;
		await unlink(path);
		await writeFile(path, "", "utf8");
	} catch {
		await writeFile(path, "", { flag: "a" });
	}
}

function isInside(root: string, value: string): boolean {
	const rel = relative(resolve(root), resolve(value));
	return rel === "" || (!rel.startsWith("..") && !rel.startsWith(`..${process.platform === "win32" ? "\\" : "/"}`));
}

export async function ensureConversationDirs(conversation: ResolvedConversation): Promise<void> {
	await mkdir(conversation.accountDir, { recursive: true });
	await mkdir(conversation.sharedDir, { recursive: true });
	await mkdir(conversation.conversationDir, { recursive: true });
	await mkdir(dirname(conversation.logPath), { recursive: true });
	await mkdir(dirname(conversation.lockPath), { recursive: true });
	await mkdir(conversation.workspaceDir, { recursive: true });
	await mkdir(conversation.gondolinDir, { recursive: true });
	await mkdir(conversation.filesDir, { recursive: true });
	await ensureRegularFile(conversation.accountMemoryPath);
	await ensureRegularFile(conversation.channelMemoryPath);
}

export async function readConversationLog(conversation: ResolvedConversation): Promise<ChatLogRecord[]> {
	try {
		const content = await readFile(conversation.logPath, "utf8");
		return content
			.split("\n")
			.map((line) => line.trim())
			.filter(Boolean)
			.map((line) => JSON.parse(line) as ChatLogRecord)
			.sort((a, b) => a.recordId - b.recordId);
	} catch {
		return [];
	}
}

export async function appendConversationRecord(
	conversation: ResolvedConversation,
	record: ChatLogRecord,
): Promise<void> {
	await ensureConversationDirs(conversation);
	await appendFile(conversation.logPath, `${JSON.stringify(record)}\n`, "utf8");
}

function extractOwnerPid(owner: string): number | undefined {
	const match = owner.match(/^pi-chat-(\d+)-/);
	if (!match) return undefined;
	const pid = Number(match[1]);
	return Number.isFinite(pid) ? pid : undefined;
}

function isPidAlive(pid: number): boolean {
	try {
		process.kill(pid, 0);
		return true;
	} catch (error) {
		const code =
			error && typeof error === "object" && "code" in error ? String((error as { code?: string }).code) : undefined;
		return code === "EPERM";
	}
}

export async function acquireConversationLock(conversation: ResolvedConversation, owner: string): Promise<void> {
	await ensureConversationDirs(conversation);
	try {
		const handle = await open(conversation.lockPath, "wx");
		try {
			await handle.writeFile(`${owner}\n`, "utf8");
		} finally {
			await handle.close();
		}
		return;
	} catch (error) {
		const code =
			error && typeof error === "object" && "code" in error ? String((error as { code?: string }).code) : undefined;
		if (code !== "EEXIST") throw error;
	}
	const existingOwner = (await readFile(conversation.lockPath, "utf8")).trim();
	const existingPid = extractOwnerPid(existingOwner);
	if (existingPid !== undefined && !isPidAlive(existingPid)) {
		await unlink(conversation.lockPath).catch(() => undefined);
		const handle = await open(conversation.lockPath, "wx");
		try {
			await handle.writeFile(`${owner}\n`, "utf8");
		} finally {
			await handle.close();
		}
		return;
	}
	throw new Error(`Conversation is already locked by ${existingOwner || "another pi-chat session"}`);
}

export async function releaseConversationLock(conversation: ResolvedConversation): Promise<void> {
	await unlink(conversation.lockPath).catch(() => undefined);
}

export async function materializeAttachments(
	conversation: ResolvedConversation,
	messageId: string,
	attachments: AttachmentInput[] | undefined,
): Promise<StoredAttachment[]> {
	if (!attachments?.length) return [];
	await ensureConversationDirs(conversation);
	const stored: StoredAttachment[] = [];
	for (const [index, attachment] of attachments.entries()) {
		const fileStats = await lstat(attachment.path);
		if (!fileStats.isFile()) throw new Error(`Attachment is not a regular file: ${attachment.path}`);
		const fileName = sanitizeFileName(attachment.name || basename(attachment.path));
		const targetPath = isInside(conversation.filesDir, attachment.path)
			? attachment.path
			: join(conversation.filesDir, `${Date.now()}-${messageId}-${index + 1}-${fileName}`);
		if (targetPath !== attachment.path) await copyFile(attachment.path, targetPath);
		stored.push({
			kind: attachment.kind || guessAttachmentKind(attachment.path),
			name: fileName,
			mimeType: attachment.mimeType || guessMimeType(attachment.path),
			size: fileStats.size,
			remoteUrl: attachment.remoteUrl,
			originalPath: targetPath === attachment.path ? undefined : attachment.path,
			localPath: targetPath,
		});
	}
	return stored;
}

export function buildBaseRecordFields(conversation: ResolvedConversation, recordId: number) {
	return {
		recordId,
		timestamp: new Date().toISOString(),
		service: conversation.service,
		accountId: conversation.accountId,
		channelKey: conversation.channelKey,
		channelId: conversation.channel.id,
		scope: "channel" as const,
	};
}

export function nextMessageId(service: string): string {
	return `${service}-${Date.now()}-${Math.random().toString(36).slice(2, 10)}`;
}

export function normalizeInboundMessage(input: InboundMessageInput, botName: string): InboundMessageInput {
	const text = input.text.trim();
	const mentionPattern = new RegExp(`@${botName.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}\\b`, "i");
	return { ...input, text, mentionedBot: input.mentionedBot ?? mentionPattern.test(text), isBot: input.isBot ?? false };
}
