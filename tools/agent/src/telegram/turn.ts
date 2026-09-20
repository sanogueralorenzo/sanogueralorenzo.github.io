import type { RuntimeClient } from "../client/client.js";
import type { Artifact, TurnRequest } from "../conversation/types.js";
import { MAX_ATTACHMENT_BYTES } from "../workspace/assets.js";
import { splitTelegramText } from "./text.js";

type TurnClient = Pick<RuntimeClient, "events" | "cancel">;

export interface TelegramTurnResult { chunks: string[]; artifacts: Artifact[] }

export function isTelegramOwner(ownerId: string | undefined, chatType: string | undefined, userId: number | undefined): boolean {
  return chatType === "private" && userId !== undefined && ownerId === String(userId);
}

export function checkTelegramVoiceSize(size: number | undefined): void {
  if (size !== undefined && size > MAX_ATTACHMENT_BYTES) throw new Error("Voice note exceeds the 25 MB limit.");
}

export class TelegramTurns {
  private active = false;

  constructor(private readonly client: TurnClient) {}

  stop(): Promise<boolean> {
    return this.client.cancel();
  }

  async run(prepare: () => Promise<Omit<TurnRequest, "channel">>): Promise<TelegramTurnResult | null> {
    if (this.active) return null;
    this.active = true;
    let output = "";
    let runtimeError = "";
    const artifacts: Artifact[] = [];
    try {
      for await (const event of this.client.events({ ...await prepare(), channel: "telegram" })) {
        if (event.type === "text_delta") output += event.delta;
        else if (event.type === "artifact") artifacts.push(event.artifact);
        else if (event.type === "error") runtimeError = event.message;
      }
      return {
        chunks: splitTelegramText([output.trim(), runtimeError].filter(Boolean).join("\n\n")),
        artifacts,
      };
    } catch (error) {
      const message = output.trim()
        ? `${output.trim()}\n\nInterrupted. Your session is saved; send another message to continue.`
        : error instanceof Error && error.name === "AbortError"
          ? "Interrupted. Your session is saved; send another message to continue."
        : error instanceof Error && /25 MB/.test(error.message)
          ? error.message
          : "I could not finish that response. Your session is saved; please try again.";
      return { chunks: [message], artifacts: [] };
    } finally {
      this.active = false;
    }
  }
}
