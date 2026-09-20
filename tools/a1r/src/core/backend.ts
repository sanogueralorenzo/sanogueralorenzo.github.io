import type { Store } from "./store.js";
import type { BackendKind, RouteDecision, Session, TurnRequest } from "./types.js";

export type BackendEvent =
  | { type: "status"; message: string }
  | { type: "text_delta"; delta: string }
  | { type: "tool_start"; name: string; callId: string }
  | { type: "tool_end"; name: string; callId: string; summary: string }
  | { type: "done"; responseId: string | null };

export interface BackendTurn {
  request: TurnRequest;
  session: Session;
  route: RouteDecision;
  instructions: string;
  memoryScope: string;
  signal?: AbortSignal;
}

export interface AgentBackend {
  readonly kind: BackendKind;
  readonly label: string;
  isConfigured(): boolean | Promise<boolean>;
  run(turn: BackendTurn): AsyncGenerator<BackendEvent>;
  close?(): void | Promise<void>;
}

export class BackendUnavailableError extends Error {
  constructor(message: string, readonly backend: BackendKind) {
    super(message);
    this.name = "BackendUnavailableError";
  }
}

export class BackendRegistry {
  constructor(
    private readonly store: Store,
    private readonly responses: AgentBackend,
    private readonly codex?: AgentBackend,
  ) {}

  selectedKind(): BackendKind | null {
    const selected = this.store.getSetting("backend");
    return selected === "codex" || selected === "responses" ? selected : null;
  }

  async resolve(): Promise<AgentBackend> {
    const selected = this.selectedKind();
    if (selected === "codex") {
      // A selected Codex backend performs its own account/allowance preflight so
      // authentication failures remain precise and we avoid duplicate RPCs.
      if (this.codex) return this.codex;
      throw new BackendUnavailableError(
        "ChatGPT needs to be reconnected. Run `a1r setup`, or choose API-key billing there.",
        "codex",
      );
    }
    if (selected === "responses") {
      if (await this.responses.isConfigured()) return this.responses;
      throw new BackendUnavailableError("An OpenAI API key is required. Run `a1r setup`.", "responses");
    }

    throw new BackendUnavailableError(
      "A1R has no selected connection. Run `a1r setup`; billing modes are never selected automatically.",
      "codex",
    );
  }
}
