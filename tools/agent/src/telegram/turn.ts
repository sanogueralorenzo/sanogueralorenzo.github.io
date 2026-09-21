import type { RuntimeClient } from "../client/client.js";
import type { Artifact, RunEnvelope, TurnRequest } from "../conversation/types.js";
import { MAX_ATTACHMENT_BYTES } from "../workspace/assets.js";
import { splitTelegramText } from "./text.js";

type TurnClient = Pick<RuntimeClient, "submit" | "stop">;

export interface TelegramTurnResult { chunks: string[]; artifacts: Artifact[] }

export function isTelegramOwner(ownerId: string | undefined, chatType: string | undefined, userId: number | undefined): boolean {
  return chatType === "private" && userId !== undefined && ownerId === String(userId);
}

export function checkTelegramVoiceSize(size: number | undefined): void {
  if (size !== undefined && size > MAX_ATTACHMENT_BYTES) throw new Error("Voice note exceeds the 25 MB limit.");
}

export function telegramFailure(error: unknown): string {
  return error instanceof Error && /25 MB/.test(error.message)
    ? error.message
    : "I could not start that response. Please try again.";
}

export class TelegramTurns {
  private current: { id: string; output: string; error: string; artifacts: Artifact[] } | null = null;
  private fresh = false;

  constructor(private readonly client: TurnClient) {}

  async submit(prepare: () => Promise<Omit<TurnRequest, "channel">>): Promise<boolean> {
    const request = { ...await prepare(), ...(this.fresh ? { fresh: true } : {}), channel: "telegram" as const };
    const accepted = await this.client.submit(request) !== null;
    if (accepted) this.fresh = false;
    return accepted;
  }

  newConversation(): void {
    this.fresh = true;
  }

  stop(): Promise<boolean> {
    return this.client.stop();
  }

  consume({ runId, event }: RunEnvelope): TelegramTurnResult | null {
    if (event.type === "turn") this.current = { id: runId, output: "", error: "", artifacts: [] };
    const current = this.current;
    if (!current || current.id !== runId) return null;
    if (event.type === "text_delta") current.output += event.delta;
    else if (event.type === "artifact") current.artifacts.push(event.artifact);
    else if (event.type === "error") current.error = event.message;
    if (event.type !== "done" && event.type !== "error") return null;
    this.current = null;
    return {
      chunks: splitTelegramText([current.output.trim(), current.error].filter(Boolean).join("\n\n")),
      artifacts: current.artifacts,
    };
  }

  interrupt(): TelegramTurnResult | null {
    const current = this.current;
    if (!current) return null;
    this.current = null;
    const message = current.output.trim()
      ? `${current.output.trim()}\n\nInterrupted. Your session is saved; send another message to continue.`
      : "Interrupted. Your session is saved; send another message to continue.";
    return { chunks: [message], artifacts: current.artifacts };
  }
}
