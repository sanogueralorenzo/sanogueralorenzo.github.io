import type { Attachment, ProgressEvent, Session, SessionCard, TurnRequest } from "./types.js";

export type BackendEvent =
  | ProgressEvent
  | { type: "done" };

export interface BackendTurn {
  request: TurnRequest;
  session: Session;
  instructions: string;
  signal?: AbortSignal;
}

export interface AgentBackend {
  transcribeAudio(attachment: Attachment, signal?: AbortSignal): Promise<string>;
  routeSession(text: string, sessions: SessionCard[], signal?: AbortSignal): Promise<string | null>;
  run(turn: BackendTurn): AsyncGenerator<BackendEvent>;
}
