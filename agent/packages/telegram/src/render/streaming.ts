// Streaming behavior adapted from Vercel Chat SDK's StreamingMarkdownRenderer
// and fallback post+edit flow (MIT).
// Source inspiration:
// - packages/chat/src/streaming-markdown.ts
// - packages/chat/src/thread.ts

import type { ChatService } from "../core/config-types.js";
import { chunkText } from "./chunking.js";
import { formatMarkdownForService, maxMessageLength } from "./format.js";
import { StreamingMarkdownRenderer } from "./streaming-markdown.js";

export interface PreviewChunk {
	id: string;
	text: string;
}

export interface PreviewTransport {
	create(text: string, parseMode?: "Markdown", replyToMessageId?: string): Promise<string>;
	edit(id: string, text: string, parseMode?: "Markdown"): Promise<void>;
	delete(id: string): Promise<void>;
}

export class StreamingPreview {
	private readonly service: ChatService;
	private readonly transport: PreviewTransport;
	private renderer = new StreamingMarkdownRenderer();
	private rawText = "";
	private chunks: PreviewChunk[] = [];
	private replyToMessageId: string | undefined;

	constructor(service: ChatService, transport: PreviewTransport) {
		this.service = service;
		this.transport = transport;
	}

	setReplyTo(messageId: string | undefined): void {
		this.replyToMessageId = messageId;
	}

	reset(): void {
		this.rawText = "";
		this.chunks = [];
		this.renderer = new StreamingMarkdownRenderer();
	}

	async clear(): Promise<void> {
		for (const chunk of this.chunks) {
			await this.transport.delete(chunk.id).catch(() => undefined);
		}
		this.reset();
	}

	async update(rawText: string, finished = false): Promise<string[]> {
		if (!rawText.startsWith(this.rawText)) {
			this.renderer.finish();
			this.reset();
		}
		const delta = rawText.slice(this.rawText.length);
		if (delta.length > 0) this.renderer.push(delta);
		this.rawText = rawText;
		const markdown = finished ? this.renderer.finish() : this.renderer.render();
		const rendered = formatMarkdownForService(this.service, markdown);
		if (rendered.text.trim().length === 0) {
			return this.chunks.map((chunk) => chunk.id);
		}
		const parts = chunkText(rendered.text, maxMessageLength(this.service)).filter((part) => part.trim().length > 0);
		if (parts.length === 0) {
			return this.chunks.map((chunk) => chunk.id);
		}
		for (let index = 0; index < parts.length; index++) {
			const text = parts[index] || " ";
			const existing = this.chunks[index];
			if (!existing) {
				const replyTo = this.chunks.length === 0 ? this.replyToMessageId : undefined;
				const id = await this.transport.create(text, rendered.parseMode, replyTo);
				this.chunks.push({ id, text });
				continue;
			}
			if (existing.text !== text) {
				await this.transport.edit(existing.id, text, rendered.parseMode);
				existing.text = text;
			}
		}
		return this.chunks.map((chunk) => chunk.id);
	}
}
