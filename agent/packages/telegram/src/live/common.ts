import { lstat, mkdir, readFile, writeFile } from "node:fs/promises";
import { basename, extname, join } from "node:path";
import type { ResolvedConversation } from "../core/config-types.js";
import type { AttachmentInput } from "../core/runtime-types.js";

function sanitize(value: string): string {
	return value.replace(/[^a-zA-Z0-9._-]+/g, "_");
}

export async function storeDownloadedAttachment(
	conversation: ResolvedConversation,
	messageId: string,
	index: number,
	fileName: string,
	data: Uint8Array,
	mimeType?: string,
	remoteUrl?: string,
): Promise<AttachmentInput> {
	await mkdir(conversation.filesDir, { recursive: true });
	const safeName = sanitize(fileName || `attachment-${index}`);
	const targetPath = join(conversation.filesDir, `incoming-${Date.now()}-${messageId}-${index}-${safeName}`);
	await writeFile(targetPath, data);
	return {
		path: targetPath,
		name: basename(targetPath),
		mimeType,
		kind: guessAttachmentKind(fileName, mimeType),
		remoteUrl,
	};
}

export function guessAttachmentKind(fileName: string, mimeType?: string): "image" | "file" | "audio" | "video" {
	const mime = mimeType?.toLowerCase() || "";
	if (mime.startsWith("image/")) return "image";
	if (mime.startsWith("audio/")) return "audio";
	if (mime.startsWith("video/")) return "video";
	const ext = extname(fileName).toLowerCase();
	if ([".png", ".jpg", ".jpeg", ".gif", ".webp"].includes(ext)) return "image";
	if ([".mp3", ".wav", ".ogg", ".m4a"].includes(ext)) return "audio";
	if ([".mp4", ".mov", ".webm"].includes(ext)) return "video";
	return "file";
}

export function guessMimeType(fileName: string): string | undefined {
	const ext = extname(fileName).toLowerCase();
	if (ext === ".png") return "image/png";
	if (ext === ".jpg" || ext === ".jpeg") return "image/jpeg";
	if (ext === ".gif") return "image/gif";
	if (ext === ".webp") return "image/webp";
	if (ext === ".mp3") return "audio/mpeg";
	if (ext === ".wav") return "audio/wav";
	if (ext === ".ogg") return "audio/ogg";
	if (ext === ".m4a") return "audio/mp4";
	if (ext === ".mp4") return "video/mp4";
	if (ext === ".mov") return "video/quicktime";
	if (ext === ".webm") return "video/webm";
	if (ext === ".pdf") return "application/pdf";
	if (ext === ".json") return "application/json";
	if (ext === ".md") return "text/markdown";
	if (ext === ".txt" || ext === ".log") return "text/plain";
	return undefined;
}

export async function readLocalAttachment(
	path: string,
): Promise<{ name: string; data: Uint8Array; mimeType?: string }> {
	const fileStats = await lstat(path);
	if (!fileStats.isFile()) throw new Error(`Attachment is not a regular file: ${path}`);
	return { name: basename(path), data: new Uint8Array(await readFile(path)), mimeType: guessMimeType(path) };
}

export async function fetchBinary(url: string, headers?: HeadersInit): Promise<Uint8Array> {
	const response = await fetch(url, { headers });
	if (!response.ok) throw new Error(`Download failed ${response.status}: ${url}`);
	return new Uint8Array(await response.arrayBuffer());
}

export function textMentionsBot(text: string, botName?: string, botUserId?: string): boolean {
	const normalized = text || "";
	if (botName) {
		const escaped = botName.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
		if (new RegExp(`@${escaped}\\b`, "i").test(normalized)) return true;
	}
	if (botUserId) {
		const escaped = botUserId.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
		if (new RegExp(`<@!?${escaped}>`).test(normalized)) return true;
		if (new RegExp(`@${escaped}\\b`, "i").test(normalized)) return true;
	}
	return false;
}
