import {
  TURN_TIMEOUT_MS,
  TurnProgressEvent,
} from "./types.js";
import { AppServerConnection } from "./connection.js";
import { asObject } from "./json.js";
import type { Turn } from "./generated/v2/Turn.js";
import {
  createRunTurnState,
  getTurnFailureMessage,
  latestTurnResponse,
} from "./turn-state.js";
import { handleTurnNotification } from "./turn-notifications.js";

export async function runTurnWithTimeout(
  client: AppServerConnection,
  threadId: string,
  text: string,
  resumeFirst: boolean,
  onTurnEvent?: (event: TurnProgressEvent) => void
): Promise<
  | { status: "completed"; response: string }
  | { status: "timed_out"; completion: Promise<{ response: string }> }
> {
  const completion = runTurn(client, threadId, text, resumeFirst, onTurnEvent);
  const raced = await waitWithTimeout(completion, TURN_TIMEOUT_MS);
  if (raced.status === "completed") {
    return {
      status: "completed",
      response: raced.value,
    };
  }

  return {
    status: "timed_out",
    completion: completion.then((response) => ({ response })),
  };
}

async function runTurn(
  client: AppServerConnection,
  threadId: string,
  text: string,
  resumeFirst: boolean,
  onTurnEvent?: (event: TurnProgressEvent) => void
): Promise<string> {
  if (resumeFirst) {
    await client.send("thread/resume", {
      threadId,
      persistExtendedHistory: false,
    });
  }

  const { state, turnDone } = createRunTurnState(threadId, onTurnEvent);
  const detachNotification = client.onNotification((notification) => {
    handleTurnNotification(state, notification);
  });

  try {
    const started = await client.send("turn/start", {
      threadId,
      input: [
        {
          type: "text",
          text,
          text_elements: [],
        },
      ],
    });

    const startedTurn = asObject(asObject(started).turn) as unknown as Turn;
    state.currentTurnId = startedTurn.id;

    switch (startedTurn.status) {
      case "completed":
        return latestTurnResponse(state);
      case "failed":
        throw new Error(getTurnFailureMessage(startedTurn));
      case "interrupted":
        throw new Error("Turn was interrupted before completion.");
      case "inProgress":
        return await turnDone;
      default:
        throw new Error(`Turn started with unexpected status: ${startedTurn.status}`);
    }
  } finally {
    detachNotification();
  }
}

async function waitWithTimeout<T>(
  promise: Promise<T>,
  timeoutMs: number
): Promise<{ status: "completed"; value: T } | { status: "timed_out" }> {
  let timeoutHandle: NodeJS.Timeout | null = null;
  try {
    const timeoutPromise = new Promise<{ status: "timed_out" }>((resolve) => {
      timeoutHandle = setTimeout(() => {
        resolve({ status: "timed_out" });
      }, timeoutMs);
    });

    const completedPromise = promise.then((value) => ({ status: "completed" as const, value }));
    return await Promise.race([completedPromise, timeoutPromise]);
  } finally {
    if (timeoutHandle) {
      clearTimeout(timeoutHandle);
    }
  }
}
