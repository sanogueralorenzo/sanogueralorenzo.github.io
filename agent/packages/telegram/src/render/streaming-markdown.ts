// Adapted from Vercel Chat SDK's StreamingMarkdownRenderer (MIT).
// Source inspiration:
// https://github.com/vercel/chat/blob/main/packages/chat/src/streaming-markdown.ts

import remend from "remend";

interface StreamingMarkdownRendererOptions {
	wrapTablesForAppend?: boolean;
}

const INLINE_MARKER_CHARS = new Set(["*", "~", "`", "["]);
const TABLE_ROW_RE = /^\|.*\|$/;
const TABLE_SEPARATOR_RE = /^\|[\s:]*-{1,}[\s:]*(\|[\s:]*-{1,}[\s:]*)*\|$/;

function isClean(text: string): boolean {
	return remend(text).length <= text.length;
}

function findCleanPrefix(text: string): string {
	if (text.length === 0 || isClean(text)) return text;
	for (let i = text.length - 1; i >= 0; i--) {
		if (!INLINE_MARKER_CHARS.has(text[i] ?? "")) continue;
		while (i > 0 && text[i - 1] === text[i]) i--;
		const candidate = text.slice(0, i);
		if (isClean(candidate)) return candidate;
	}
	return "";
}

function isInsideCodeFence(text: string): boolean {
	let inside = false;
	for (const line of text.split("\n")) {
		const trimmed = line.trimStart();
		if (trimmed.startsWith("```") || trimmed.startsWith("~~~")) inside = !inside;
	}
	return inside;
}

function getCommittablePrefix(text: string): string {
	const endsWithNewline = text.endsWith("\n");
	const lines = text.split("\n");
	if (!endsWithNewline && lines.length > 0) lines.pop();
	if (endsWithNewline && lines.length > 0 && lines.at(-1) === "") lines.pop();

	let heldCount = 0;
	let separatorFound = false;
	for (let i = lines.length - 1; i >= 0; i--) {
		const trimmed = lines[i]?.trim() ?? "";
		if (trimmed.length === 0) break;
		if (TABLE_SEPARATOR_RE.test(trimmed)) {
			separatorFound = true;
			heldCount++;
			continue;
		}
		if (TABLE_ROW_RE.test(trimmed)) {
			heldCount++;
			continue;
		}
		break;
	}

	if (heldCount === 0) return text;
	if (!separatorFound) {
		const safeLines = lines.slice(0, Math.max(0, lines.length - heldCount));
		return safeLines.join("\n") + (safeLines.length > 0 ? "\n" : "");
	}
	return text;
}

function wrapTablesForAppend(text: string, closeFences = false): string {
	const lines = text.split("\n");
	const out: string[] = [];
	let inTable = false;
	for (const line of lines) {
		if (!inTable && TABLE_ROW_RE.test(line.trim()) && !isInsideCodeFence(out.join("\n"))) {
			inTable = true;
			out.push("```");
			out.push(line);
			continue;
		}
		if (inTable && !TABLE_ROW_RE.test(line.trim()) && !TABLE_SEPARATOR_RE.test(line.trim())) {
			out.push("```");
			inTable = false;
		}
		out.push(line);
	}
	if (inTable && closeFences) out.push("```");
	return out.join("\n");
}

export class StreamingMarkdownRenderer {
	private accumulated = "";
	private dirty = true;
	private cachedRender = "";
	private finished = false;
	private fenceToggles = 0;
	private incompleteLine = "";
	private readonly options: Required<StreamingMarkdownRendererOptions>;

	constructor(options: StreamingMarkdownRendererOptions = {}) {
		this.options = { wrapTablesForAppend: options.wrapTablesForAppend ?? true };
	}

	push(chunk: string): void {
		this.accumulated += chunk;
		this.dirty = true;
		this.incompleteLine += chunk;
		const parts = this.incompleteLine.split("\n");
		this.incompleteLine = parts.pop() ?? "";
		for (const line of parts) {
			const trimmed = line.trimStart();
			if (trimmed.startsWith("```") || trimmed.startsWith("~~~")) this.fenceToggles++;
		}
	}

	private isAccumulatedInsideFence(): boolean {
		let inside = this.fenceToggles % 2 === 1;
		const trimmed = this.incompleteLine.trimStart();
		if (trimmed.startsWith("```") || trimmed.startsWith("~~~")) inside = !inside;
		return inside;
	}

	render(): string {
		if (!this.dirty) return this.cachedRender;
		this.dirty = false;
		if (this.finished) {
			this.cachedRender = remend(this.accumulated);
			return this.cachedRender;
		}
		if (this.isAccumulatedInsideFence()) {
			this.cachedRender = remend(this.accumulated);
			return this.cachedRender;
		}
		this.cachedRender = remend(getCommittablePrefix(this.accumulated));
		return this.cachedRender;
	}

	getCommittableText(): string {
		if (this.finished) return this.formatAppendOnlyText(this.accumulated, true);
		let text = this.accumulated;
		if (text.length > 0 && !text.endsWith("\n")) {
			const lastNewline = text.lastIndexOf("\n");
			const withoutIncomplete = lastNewline >= 0 ? text.slice(0, lastNewline + 1) : "";
			if (!isInsideCodeFence(withoutIncomplete)) text = withoutIncomplete;
		}
		if (isInsideCodeFence(text)) return this.formatAppendOnlyText(text);
		const committed = getCommittablePrefix(text);
		const wrapped = this.formatAppendOnlyText(committed);
		if (isInsideCodeFence(wrapped)) return wrapped;
		return findCleanPrefix(wrapped);
	}

	getText(): string {
		return this.accumulated;
	}

	finish(): string {
		this.finished = true;
		this.dirty = true;
		return this.render();
	}

	private formatAppendOnlyText(text: string, closeFences = false): string {
		if (!this.options.wrapTablesForAppend) return text;
		return wrapTablesForAppend(text, closeFences);
	}
}
