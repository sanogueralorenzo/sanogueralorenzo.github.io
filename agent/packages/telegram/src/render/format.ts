// Formatting adapted from Vercel Chat SDK service converters (MIT).
// Source inspiration:
// - packages/adapter-telegram/src/markdown.ts

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

export function formatMarkdownForService(_service: ChatService, markdown: string): RenderedChunkPayload {
	return { text: normalizeTelegram(markdown), parseMode: "Markdown" };
}

export function maxMessageLength(_service: ChatService): number {
	return 4096;
}
