import type { Attachment, ProgressEvent, Session, SessionCard, TurnRequest } from "./types.js";

export type BackendEvent =
  | ProgressEvent
  | { type: "done" };

export type Handoff = { destination: { sessionId: string } | { cwd: string }; task: string | null };

export interface BackendTurn {
  request: TurnRequest;
  session: Session;
  instructions: string;
  signal?: AbortSignal;
}

export interface RouteTurn {
  request: TurnRequest;
  session: Session;
  sessionTools: SessionCard[];
  signal?: AbortSignal;
}

export interface AgentBackend {
  transcribeAudio(attachment: Attachment, signal?: AbortSignal): Promise<string>;
  route(turn: RouteTurn): Promise<Handoff | null>;
  steer(sessionId: string, text: string): Promise<boolean>;
  run(turn: BackendTurn): AsyncGenerator<BackendEvent>;
}
