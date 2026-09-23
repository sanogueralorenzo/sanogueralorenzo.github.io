import { on } from "node:events";
import type { Attachment } from "../conversation/types.js";
import { UTILITY_MODEL } from "../local/config.js";
import { readVoiceNote } from "../workspace/audio.js";
import type { CodexAppServer } from "./app-server.js";
import { nextForThread, type Notifications } from "./notifications.js";
import type { RealtimePeer } from "./webrtc.js";

async function nextRealtime(queue: Notifications, threadId: string) {
  const event = await nextForThread(queue, threadId);
  if (event.method === "thread/realtime/error") throw new Error(String(event.params.message ?? "Voice transcription failed."));
  return event;
}

export async function transcribeVoice(
  client: CodexAppServer,
  homeDir: string,
  attachment: Attachment,
  createPeer: () => RealtimePeer,
  signal?: AbortSignal,
): Promise<string> {
  const audio = await readVoiceNote(attachment);
  const started = await client.request<{ thread: { id: string } }>("thread/start", {
    model: UTILITY_MODEL,
    cwd: homeDir,
    sandbox: "danger-full-access",
    approvalPolicy: "never",
    ephemeral: true,
    threadSource: "appServer",
  });
  const threadId = started.thread.id;
  const lifetime = new AbortController();
  const timeout = AbortSignal.timeout(45_000);
  const combined = signal ? AbortSignal.any([signal, timeout]) : timeout;
  const queue = on(client, "notification", { signal: AbortSignal.any([combined, lifetime.signal]) }) as Notifications;
  const peer = createPeer();
  try {
    await client.request("thread/realtime/start", {
      threadId,
      outputModality: "audio",
      includeStartupContext: false,
      clientManagedHandoffs: true,
      flushTranscriptTailOnSessionEnd: true,
      realtimeStartInstructions: "Transcribe the user's speech accurately.",
      version: "v3",
      transport: { type: "webrtc", sdp: await peer.offer() },
    });
    while (true) {
      const event = await nextRealtime(queue, threadId);
      if (event.method === "thread/realtime/sdp" && typeof event.params.sdp === "string") {
        await peer.accept(event.params.sdp);
        break;
      }
    }
    await peer.sendAudio(audio, combined);
    while (true) {
      const event = await nextRealtime(queue, threadId);
      if (event.method === "thread/realtime/closed") throw new Error("Voice transcription ended before a transcript was ready.");
      if (event.method === "thread/realtime/transcript/done" && event.params.role === "user") {
        const transcript = String(event.params.text ?? "").trim();
        if (!transcript) throw new Error("The voice note did not contain recognizable speech.");
        return transcript;
      }
    }
  } catch (error) {
    if (timeout.aborted && !signal?.aborted) throw new Error("Voice transcription timed out.");
    throw error;
  } finally {
    await client.request("thread/realtime/stop", { threadId }).catch(() => undefined);
    await peer.close().catch(() => undefined);
    lifetime.abort();
  }
}
