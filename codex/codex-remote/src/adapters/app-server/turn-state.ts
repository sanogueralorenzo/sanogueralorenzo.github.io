import { TurnProgressEvent } from "./types.js";
import { asObject, getString } from "./json.js";

export type RunTurnState = {
  threadId: string;
  currentTurnId: string | null;
  lastAgentMessage: string;
  lastFinalAgentMessage: string;
  agentSnapshots: Map<string, string>;
  emitTurnEvent: (event: TurnProgressEvent) => void;
  finalizeSuccess: (value: string) => void;
  finalizeFailure: (error: unknown) => void;
};

export function createRunTurnState(
  threadId: string,
  onTurnEvent?: (event: TurnProgressEvent) => void
): { state: RunTurnState; turnDone: Promise<string> } {
  let finished = false;
  let resolveTurn: (value: string) => void = () => {};
  let rejectTurn: (reason: unknown) => void = () => {};
  const turnDone = new Promise<string>((resolve, reject) => {
    resolveTurn = resolve;
    rejectTurn = reject;
  });

  return {
    state: {
      threadId,
      currentTurnId: null,
      lastAgentMessage: "",
      lastFinalAgentMessage: "",
      agentSnapshots: new Map<string, string>(),
      emitTurnEvent: (event) => {
        if (!onTurnEvent) {
          return;
        }
        try {
          onTurnEvent(event);
        } catch {
          // Progress consumers are best-effort and must not break turn handling.
        }
      },
      finalizeSuccess: (value) => {
        if (finished) {
          return;
        }
        finished = true;
        resolveTurn(value);
      },
      finalizeFailure: (error) => {
        if (finished) {
          return;
        }
        finished = true;
        rejectTurn(error);
      },
    },
    turnDone,
  };
}

export function latestTurnResponse(state: RunTurnState): string {
  return (state.lastFinalAgentMessage || state.lastAgentMessage).trim();
}

export function getTurnFailureMessage(turn: Record<string, unknown>): string {
  const error = asObject(turn.error);
  const message = getString(error.message);
  const details = getString(error.additionalDetails);

  if (message && details) {
    return `${message}\n${details}`;
  }
  if (message) {
    return message;
  }
  return "Turn failed.";
}
