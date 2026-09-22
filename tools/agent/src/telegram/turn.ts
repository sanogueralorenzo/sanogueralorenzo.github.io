import type { RuntimeClient } from "../client/client.js";
import type { Artifact, RunEnvelope, RuntimeSnapshot, TurnRequest } from "../conversation/types.js";
import { MAX_ATTACHMENT_BYTES } from "../workspace/assets.js";
import { splitTelegramText } from "./text.js";

type TurnClient = Pick<RuntimeClient, "submit" | "stop">;

export interface TelegramTurnResult { chunks: string[]; artifacts: Artifact[] }
export interface TelegramSubmitResult { accepted: boolean; recovered: TelegramTurnResult | null }

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
  private pendingId: string | undefined;
  private deliveredId: string | undefined;
  private latestSnapshot: RuntimeSnapshot | undefined;

  constructor(private readonly client: TurnClient) {}

  async submit(prepare: () => Promise<Omit<TurnRequest, "channel">>): Promise<TelegramSubmitResult> {
    const request = { ...await prepare(), ...(this.fresh ? { fresh: true } : {}), channel: "telegram" as const };
    const run = await this.client.submit(request);
    if (!run) return { accepted: false, recovered: null };
    this.fresh = false;
    this.pendingId = this.deliveredId === run.id ? undefined : run.id;
    const recovered = this.latestSnapshot?.lastRun?.id === run.id && !this.latestSnapshot.activeRun
      ? this.reconcile(this.latestSnapshot)
      : null;
    return { accepted: true, recovered };
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
    else if (event.type === "navigate") current.output = `Resumed “${event.session.title}”.`;
    else if (event.type === "artifact") current.artifacts.push(event.artifact);
    else if (event.type === "error") current.error = event.message;
    if (event.type !== "done" && event.type !== "error") return null;
    this.current = null;
    this.deliveredId = runId;
    if (this.pendingId === runId) this.pendingId = undefined;
    return {
      chunks: splitTelegramText([current.output.trim(), current.error].filter(Boolean).join("\n\n")),
      artifacts: current.artifacts,
    };
  }

  reconcile(snapshot: RuntimeSnapshot): TelegramTurnResult | null {
    this.latestSnapshot = snapshot;
    const previous = this.current;
    const active = snapshot.activeRun;
    this.current = active
      ? { id: active.run.id, output: active.navigation ? `Resumed “${active.navigation.session.title}”.` : active.output, error: "", artifacts: active.artifacts }
      : null;
    const pendingId = previous?.id ?? this.pendingId;
    if (!pendingId || pendingId === active?.run.id || pendingId === this.deliveredId) return null;
    if (!previous && snapshot.lastRun?.id !== pendingId) return null;
    this.deliveredId = pendingId;
    if (this.pendingId === pendingId) this.pendingId = undefined;
    const saved = snapshot.lastRun?.id === pendingId
      && snapshot.transcript?.session.id === snapshot.lastRun.sessionId
      ? snapshot.transcript.messages.at(-1)
      : null;
    const output = saved?.role === "assistant"
      ? saved.content
      : [previous?.output.trim(), "Response ended while reconnecting. Send another message to continue."].filter(Boolean).join("\n\n");
    return { chunks: splitTelegramText(output), artifacts: previous?.artifacts ?? [] };
  }
}
