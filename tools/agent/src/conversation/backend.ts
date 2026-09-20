import type { Store } from "./store.js";
import type { Attachment, BackendKind, ProgressEvent, RouteDecision, Session, TurnRequest } from "./types.js";

export type BackendEvent =
  | ProgressEvent
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
  transcribeAudio(attachment: Attachment, signal?: AbortSignal): Promise<string>;
  run(turn: BackendTurn): AsyncGenerator<BackendEvent>;
}

export class BackendRegistry {
  constructor(
    private readonly store: Store,
    private readonly responses: AgentBackend,
    private readonly codex: AgentBackend,
  ) {}

  resolve(): AgentBackend {
    const selected = this.store.getSetting("backend");
    if (selected === "codex") return this.codex;
    if (selected === "responses") return this.responses;
    throw new Error("Agent has no selected connection. Run `agent setup`; billing modes are never selected automatically.");
  }
}
