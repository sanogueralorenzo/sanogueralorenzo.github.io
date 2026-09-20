import type { Store } from "./store.js";
import type { Artifact, Attachment, BackendKind, RouteDecision, Session, TurnRequest } from "./types.js";

export type BackendEvent =
  | { type: "status"; message: string }
  | { type: "text_delta"; delta: string }
  | { type: "artifact"; artifact: Artifact }
  | { type: "tool_start"; name: string; callId: string }
  | { type: "tool_end"; name: string; callId: string; summary: string }
  | { type: "done" };

export interface BackendTurn {
  request: TurnRequest;
  session: Session;
  route: RouteDecision;
  instructions: string;
  workerInstructions: string;
  memoryScope: string;
  signal?: AbortSignal;
}

export interface AgentBackend {
  readonly kind: BackendKind;
  isConfigured(): boolean | Promise<boolean>;
  transcribeAudio(attachment: Attachment, signal?: AbortSignal): Promise<string>;
  run(turn: BackendTurn): AsyncGenerator<BackendEvent>;
  close?(): void | Promise<void>;
}

export class BackendRegistry {
  constructor(
    private readonly store: Store,
    private readonly responses: AgentBackend,
    private readonly codex?: AgentBackend,
  ) {}

  async resolve(): Promise<AgentBackend> {
    const selected = this.store.getSetting("backend");
    if (selected === "codex") {
      if (this.codex) return this.codex;
      throw new Error("ChatGPT needs to be reconnected. Run `agent setup`, or choose API-key billing there.");
    }
    if (selected === "responses") {
      if (await this.responses.isConfigured()) return this.responses;
      throw new Error("An OpenAI API key is required. Run `agent setup`.");
    }
    throw new Error("Agent has no selected connection. Run `agent setup`; billing modes are never selected automatically.");
  }
}
