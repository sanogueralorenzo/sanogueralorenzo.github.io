import {
  TURN_TIMEOUT_MS,
  TurnCompletion,
  TurnRuntimeOptions,
} from "./types.js";
import { AppServerConnection } from "./connection.js";
import { asObject } from "./json.js";
import type { Turn } from "./generated/v2/Turn.js";
import {
  createRunTurnState,
  getTurnFailureMessage,
  latestTurnCompletion,
} from "./turn-state.js";
import { handleTurnNotification } from "./turn-notifications.js";

export async function runTurnWithTimeout(
  client: AppServerConnection,
  threadId: string,
  text: string,
  resumeFirst: boolean,
  runtimeOptions?: TurnRuntimeOptions
): Promise<
  | { status: "completed"; response: string; imagePaths?: string[] }
  | { status: "timed_out"; completion: Promise<TurnCompletion> }
> {
  const completion = runTurn(client, threadId, text, resumeFirst, runtimeOptions);
  const raced = await waitWithTimeout(completion, TURN_TIMEOUT_MS);
  if (raced.status === "completed") {
    return {
      status: "completed",
      response: raced.value.response,
      imagePaths: raced.value.imagePaths,
    };
  }

  return {
    status: "timed_out",
    completion,
  };
}

async function runTurn(
  client: AppServerConnection,
  threadId: string,
  text: string,
  resumeFirst: boolean,
  runtimeOptions?: TurnRuntimeOptions
): Promise<TurnCompletion> {
  const { state, turnDone } = createRunTurnState(threadId, runtimeOptions?.onTurnEvent);
  const unregisterRuntimeOptions = runtimeOptions
    ? client.registerRuntimeOptions(runtimeOptions, threadId)
    : () => {};

  const detachNotification = client.onNotification((notification) => {
    handleTurnNotification(state, notification);
  });

  try {
    if (resumeFirst) {
      await client.send("thread/resume", { threadId });
    }

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
        return latestTurnCompletion(state);
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
    unregisterRuntimeOptions();
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
