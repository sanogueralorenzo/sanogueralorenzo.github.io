import type { Attachment, ProgressEvent, Session, TurnRequest } from "./types.js";

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
  run(turn: BackendTurn): AsyncGenerator<BackendEvent>;
}
