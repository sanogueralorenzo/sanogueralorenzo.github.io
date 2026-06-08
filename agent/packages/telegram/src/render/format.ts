// Formatting adapted from Vercel Chat SDK service converters (MIT).
// Source inspiration:
// - packages/adapter-telegram/src/markdown.ts
// - packages/adapter-discord/src/markdown.ts

import type { ChatService } from "../core/config-types.js";

export interface RenderedChunkPayload {
	text: string;
	parseMode?: "Markdown";
}

function normalizeTelegram(markdown: string): string {
	return markdown
		.replace(/\|(.+)\|/g, (match) => (match.includes("\n") ? match : match))
		.replace(/\r\n/g, "\n")
		.trim();
}

function normalizeDiscord(markdown: string): string {
	return markdown.replace(/(?<!<)@(\w+)/g, "<@$1>").trim();
}

export function formatMarkdownForService(service: ChatService, markdown: string): RenderedChunkPayload {
	if (service === "telegram") return { text: normalizeTelegram(markdown), parseMode: "Markdown" };
	return { text: normalizeDiscord(markdown) };
}

export function maxMessageLength(service: ChatService): number {
	if (service === "telegram") return 4096;
	return 2000;
}
