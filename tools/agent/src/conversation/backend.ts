import type { Attachment, ProgressEvent, RouteDecision, Session, TurnRequest } from "./types.js";

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
