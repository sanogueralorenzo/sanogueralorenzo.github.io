import { TurnCompletion, TurnProgressEvent } from "./types.js";
import type { Turn } from "./generated/v2/Turn.js";

export type RunTurnState = {
  threadId: string;
  currentTurnId: string | null;
  lastAgentMessage: string;
  lastFinalAgentMessage: string;
  imagePaths: string[];
  agentSnapshots: Map<string, string>;
  emitTurnEvent: (event: TurnProgressEvent) => void;
  finalizeSuccess: (value: TurnCompletion) => void;
  finalizeFailure: (error: unknown) => void;
};

export function createRunTurnState(
  threadId: string,
  onTurnEvent?: (event: TurnProgressEvent) => void
): { state: RunTurnState; turnDone: Promise<TurnCompletion> } {
  let finished = false;
  let resolveTurn: (value: TurnCompletion) => void = () => {};
  let rejectTurn: (reason: unknown) => void = () => {};
  const turnDone = new Promise<TurnCompletion>((resolve, reject) => {
    resolveTurn = resolve;
    rejectTurn = reject;
  });

  return {
    state: {
      threadId,
      currentTurnId: null,
      lastAgentMessage: "",
      lastFinalAgentMessage: "",
      imagePaths: [],
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

export function latestTurnCompletion(state: RunTurnState): TurnCompletion {
  return {
    response: latestTurnResponse(state),
    imagePaths: [...state.imagePaths],
  };
}

export function getTurnFailureMessage(turn: Turn): string {
  if (turn.error?.message && turn.error.additionalDetails) {
    return `${turn.error.message}\n${turn.error.additionalDetails}`;
  }
  if (turn.error?.message) {
    return turn.error.message;
  }
  return "Turn failed.";
}
