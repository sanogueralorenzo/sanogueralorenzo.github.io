import { type ChildProcessWithoutNullStreams, spawn } from "node:child_process";
import { dirname, join } from "node:path";
import { createInterface } from "node:readline";
import { fileURLToPath } from "node:url";

import type { StoredAttachment } from "./core/runtime-types.js";

interface PendingRequest {
	resolve: (result: string) => void;
	reject: (error: Error) => void;
}

class SttWorker {
	private process: ChildProcessWithoutNullStreams | undefined;
	private nextId = 1;
	private pending = new Map<number, PendingRequest>();

	async transcribe(path: string): Promise<string> {
		this.ensureStarted();
		const id = this.nextId++;
		return new Promise((resolve, reject) => {
			this.pending.set(id, { resolve, reject });
			this.process?.stdin.write(
				`${JSON.stringify({
					id,
					path,
					model: process.env.PI_CHAT_STT_MODEL || "base",
					language: process.env.PI_CHAT_STT_LANGUAGE || "en",
				})}\n`,
			);
		});
	}

	private ensureStarted(): void {
		if (this.process) return;
		const workerPath = join(dirname(fileURLToPath(import.meta.url)), "stt-worker.py");
		const python =
			process.env.PI_CHAT_STT_PYTHON ||
			(process.env.HOME ? join(process.env.HOME, ".hermes/hermes-agent/.venv/bin/python") : undefined) ||
			"python3";
		this.process = spawn(python, [workerPath], { stdio: ["pipe", "pipe", "pipe"] });
		const rl = createInterface({ input: this.process.stdout });
		rl.on("line", (line) => this.handleLine(line));
		this.process.stderr.on("data", (chunk) => process.stderr.write(`[pi-chat-stt] ${chunk}`));
		this.process.on("exit", (code, signal) => {
			const error = new Error(`STT worker exited (${code ?? signal ?? "unknown"})`);
			for (const pending of this.pending.values()) pending.reject(error);
			this.pending.clear();
			this.process = undefined;
		});
	}

	private handleLine(line: string): void {
		let message: { id?: number; ok?: boolean; text?: string; error?: string; type?: string };
		try {
			message = JSON.parse(line);
		} catch {
			process.stderr.write(`[pi-chat-stt] ${line}\n`);
			return;
		}
		if (message.type === "ready") return;
		if (typeof message.id !== "number") return;
		const pending = this.pending.get(message.id);
		if (!pending) return;
		this.pending.delete(message.id);
		if (message.ok) pending.resolve(message.text || "");
		else pending.reject(new Error(message.error || "STT failed"));
	}
}

const sttWorker = new SttWorker();

function sttEnabled(): boolean {
	return !/^(0|false|no)$/i.test(process.env.PI_CHAT_STT_ENABLED ?? "1");
}

function isAudioAttachment(attachment: StoredAttachment): boolean {
	return attachment.kind === "audio" || (attachment.mimeType?.startsWith("audio/") ?? false);
}

export async function transcribeInboundAudio(text: string, attachments: StoredAttachment[]): Promise<string> {
	if (!sttEnabled()) return text;
	const audioAttachments = attachments.filter(isAudioAttachment);
	if (audioAttachments.length === 0) return text;
	const transcripts: string[] = [];
	for (const attachment of audioAttachments) {
		try {
			const transcript = (await sttWorker.transcribe(attachment.localPath)).trim();
			if (transcript) transcripts.push(transcript);
		} catch (error) {
			const message = error instanceof Error ? error.message : String(error);
			transcripts.push(`[Voice transcription failed: ${message}]`);
		}
	}
	if (transcripts.length === 0) return text;
	return [text.trim(), ...transcripts].filter(Boolean).join("\n");
}
