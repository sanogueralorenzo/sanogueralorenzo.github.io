import { readFile } from "node:fs/promises";
import CodecParser, { type OggPage } from "codec-parser";
import type { Attachment } from "../conversation/types.js";

interface OpusFrame {
  data: Buffer;
  samples: number;
  durationMs: number;
}

export interface OpusAudio {
  frames: OpusFrame[];
}

const MAX_VOICE_DURATION_MS = 10 * 60_000;

export async function readVoiceNote(attachment: Attachment): Promise<OpusAudio> {
  if (attachment.mimeType !== "audio/ogg" && attachment.mimeType !== "audio/opus") {
    throw new Error("ChatGPT voice notes must use Ogg Opus audio.");
  }
  const parser = new CodecParser<OggPage>("audio/ogg");
  const pages = parser.parseAll(new Uint8Array(await readFile(attachment.path)));
  const frames = pages.flatMap((page) => page.codecFrames).map((frame) => ({
    data: Buffer.from(frame.data),
    samples: frame.samples,
    durationMs: frame.duration,
  }));
  const durationMs = frames.reduce((total, frame) => total + frame.durationMs, 0);
  if (frames.length === 0 || durationMs === 0) throw new Error("The voice note is empty.");
  if (durationMs > MAX_VOICE_DURATION_MS) throw new Error("Voice note exceeds the 10 minute limit.");
  return { frames };
}
