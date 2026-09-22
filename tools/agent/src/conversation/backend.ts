import type { Attachment, ProgressEvent, Session, SessionCard, TurnRequest } from "./types.js";

export type BackendEvent =
  | ProgressEvent
  | { type: "navigate"; sessionId: string }
  | { type: "workspace"; cwd: string }
  | { type: "done" };

export interface BackendTurn {
  request: TurnRequest;
  session: Session;
  instructions: string;
  sessionTools?: SessionCard[];
  signal?: AbortSignal;
}

export interface AgentBackend {
  transcribeAudio(attachment: Attachment, signal?: AbortSignal): Promise<string>;
  discardSession(sessionId: string): Promise<void>;
  run(turn: BackendTurn): AsyncGenerator<BackendEvent>;
}
