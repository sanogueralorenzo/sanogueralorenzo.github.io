import type { RuntimeClient } from "../client/client.js";
import type { Artifact, RunEnvelope, RuntimeSnapshot, Session, TurnRequest } from "../conversation/types.js";
import { MAX_ATTACHMENT_BYTES } from "../workspace/assets.js";
import { redactSecrets } from "../workspace/security.js";
import { splitTelegramText } from "./text.js";

type TurnClient = Pick<RuntimeClient, "submit" | "stop" | "telegramSession" | "transcript">;
type InFlight = { sessionId: string; output: string; error: string; artifacts: Artifact[] };

export interface TelegramTurnResult { sessionId: string; chunks: string[]; artifacts: Artifact[] }
export interface TelegramSubmitResult { accepted: boolean; recovered: TelegramTurnResult[] }

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
  private current = new Map<string, InFlight>();
  private pending = new Map<string, string>();
  private delivered = new Set<string>();
  private sessionId: string | undefined;
  private latestSnapshot: RuntimeSnapshot | undefined;

  constructor(private readonly client: TurnClient, private readonly ownerId: () => string | undefined) {}

  get selectedSessionId(): string | undefined { return this.sessionId; }

  async ensureSession(): Promise<string> {
    const owner = this.ownerId();
    if (!owner) throw new Error("Telegram is not paired.");
    const session = await this.client.telegramSession(owner);
    this.sessionId = session.id;
    return session.id;
  }

  async submit(prepare: () => Promise<Omit<TurnRequest, "channel">>): Promise<TelegramSubmitResult> {
    const sessionId = await this.ensureSession();
    const run = await this.client.submit({ ...await prepare(), sessionId, channel: "telegram" });
    if (!run) return { accepted: false, recovered: [] };
    this.pending.set(run.id, run.sessionId);
    const recovered = this.latestSnapshot?.lastRuns.some((last) => last.id === run.id)
      ? await this.reconcile(this.latestSnapshot) : [];
    return { accepted: true, recovered };
  }

  async newConversation(): Promise<void> {
    const owner = this.ownerId();
    if (!owner) throw new Error("Telegram is not paired.");
    this.sessionId = (await this.client.telegramSession(owner, { fresh: true })).id;
    this.current.clear();
    this.pending.clear();
    this.latestSnapshot = undefined;
  }

  async selectConversation(sessionId: string): Promise<Session> {
    const owner = this.ownerId();
    if (!owner) throw new Error("Telegram is not paired.");
    const session = await this.client.telegramSession(owner, { sessionId });
    if (session.id !== this.sessionId) {
      this.sessionId = session.id;
      this.current.clear();
      this.pending.clear();
      this.latestSnapshot = undefined;
    }
    return session;
  }

  hasActiveRun(): boolean { return this.current.size > 0; }

  stop(): Promise<boolean> {
    const runId = [...this.current].find(([, run]) => run.sessionId === this.sessionId)?.[0]
      ?? [...this.pending].find(([, sessionId]) => sessionId === this.sessionId)?.[0];
    return runId ? this.client.stop(runId) : Promise.resolve(false);
  }

  consume({ sessionId, runId, event }: RunEnvelope): TelegramTurnResult | null {
    if (sessionId !== this.sessionId && !this.current.has(runId)) return null;
    if (event.type === "turn") {
      this.current.set(runId, { sessionId, output: "", error: "", artifacts: [] });
      if (event.channel === "telegram") return null;
      const source = event.channel === "macos" ? "Mac" : event.channel.toUpperCase();
      const input = redactSecrets(event.text.trim()) || (event.hasAttachments ? "Voice message" : "Message");
      return { sessionId, chunks: splitTelegramText(`You (${source}): ${input}`), artifacts: [] };
    }
    const current = this.current.get(runId);
    if (!current || this.delivered.has(runId)) return null;
    if (event.type === "text_delta") current.output += event.delta;
    else if (event.type === "navigate") {
      current.output = `Resumed “${event.session.title}”.`;
      if (this.sessionId === sessionId) this.sessionId = event.session.id;
    }
    else if (event.type === "artifact") current.artifacts.push(event.artifact);
    else if (event.type === "error") current.error = event.message;
    if (event.type !== "done" && event.type !== "error") return null;
    this.current.delete(runId);
    this.pending.delete(runId);
    this.markDelivered(runId);
    return {
      sessionId,
      chunks: splitTelegramText([current.output.trim(), current.error].filter(Boolean).join("\n\n")),
      artifacts: current.artifacts,
    };
  }

  async reconcile(snapshot: RuntimeSnapshot): Promise<TelegramTurnResult[]> {
    this.latestSnapshot = snapshot;
    const previous = this.current;
    const activeRuns = snapshot.activeRuns.filter((active) =>
      active.run.sessionId === this.sessionId || active.navigation?.session.id === this.sessionId);
    this.current = new Map(activeRuns.map((active) => [active.run.id, {
      sessionId: active.run.sessionId,
      output: active.navigation ? `Resumed “${active.navigation.session.title}”.` : active.output,
      error: "",
      artifacts: active.artifacts,
    }]));
    for (const active of activeRuns) {
      if (active.navigation && this.sessionId === active.run.sessionId) this.sessionId = active.navigation.session.id;
    }
    const recovered: TelegramTurnResult[] = [];
    for (const [runId, sessionId] of new Map([
      ...[...previous].map(([id, run]) => [id, run.sessionId] as const),
      ...this.pending,
    ])) {
      if (this.current.has(runId) || this.delivered.has(runId)) continue;
      const last = snapshot.lastRuns.find((run) => run.id === runId && run.sessionId === sessionId);
      if (!last) continue;
      const transcript = snapshot.transcript?.session.id === sessionId
        ? snapshot.transcript : await this.client.transcript(sessionId);
      const saved = transcript.messages.at(-1);
      const output = saved?.role === "assistant" ? saved.content : previous.get(runId)?.output ?? "";
      recovered.push({ sessionId, chunks: splitTelegramText(output || "Response ended while reconnecting."), artifacts: previous.get(runId)?.artifacts ?? [] });
      this.pending.delete(runId);
      this.markDelivered(runId);
    }
    return recovered;
  }

  private markDelivered(runId: string): void {
    this.delivered.add(runId);
    if (this.delivered.size > 100) this.delivered.delete(this.delivered.values().next().value!);
  }
}
