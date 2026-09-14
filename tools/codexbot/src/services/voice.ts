import { execFile } from "node:child_process";
import { mkdtemp, rm, writeFile } from "node:fs/promises";
import { basename, join, resolve } from "node:path";
import { tmpdir } from "node:os";
import { promisify } from "node:util";
import { PromptContext } from "../bot/context.js";

const execFileAsync = promisify(execFile);

type VoiceServiceDeps = {
  token: string;
  projectRoot: string;
};

export function createVoiceService(deps: VoiceServiceDeps) {
  const transcribeScriptPath = resolve(deps.projectRoot, "scripts/transcribe-whispercpp.sh");

  async function transcribeVoiceByFileId(api: PromptContext["api"], fileId: string): Promise<string> {
    const file = await api.getFile(fileId);
    const filePath = file.file_path;
    if (!filePath) {
      throw new Error("Telegram did not return a file path for this voice message.");
    }

    const downloadUrl = `https://api.telegram.org/file/bot${deps.token}/${filePath}`;
    const response = await fetch(downloadUrl);
    if (!response.ok) {
      throw new Error(`Failed to download voice file from Telegram (HTTP ${response.status}).`);
    }

    const data = Buffer.from(await response.arrayBuffer());
    const tempDir = await mkdtemp(join(tmpdir(), "tg-voice-"));
    const localFile = join(tempDir, basename(filePath) || "voice.oga");
    await writeFile(localFile, data);

    try {
      const { stdout, stderr } = await execFileAsync("bash", [transcribeScriptPath, localFile], {
        maxBuffer: 10 * 1024 * 1024
      });

      const transcript = stdout.trim();
      if (!transcript) {
        const stderrText = String(stderr ?? "").trim();
        if (stderrText) {
          throw new Error(`Transcriber returned empty output.\n\n${stderrText}`);
        }
        throw new Error("Transcriber returned empty output.");
      }
      return transcript;
    } finally {
      await rm(tempDir, { recursive: true, force: true });
    }
  }

  async function transcribeVoiceMessage(ctx: PromptContext): Promise<string> {
    const fileId = ctx.message.voice?.file_id;
    if (!fileId) {
      throw new Error("No voice payload found.");
    }
    return transcribeVoiceByFileId(ctx.api, fileId);
  }

  return {
    transcribeVoiceMessage,
    transcribeVoiceByFileId
  };
}

export function limitTelegramText(value: string, max = 3500): string {
  if (value.length <= max) {
    return value;
  }
  return `${value.slice(0, max - 3)}...`;
}
