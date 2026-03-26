import {
  ConversationOptions,
  TimedCreateTurnResult,
  TimedTurnResult,
  TurnRuntimeOptions,
} from "./types.js";
import { withTurnClient } from "./connection.js";
import { runTurnWithTimeout } from "./turn-runner.js";
import { startThreadOnClient } from "./threads.js";

export async function sendMessageWithTimeoutContinuation(
  threadId: string,
  text: string,
  runtimeOptions?: TurnRuntimeOptions
): Promise<TimedTurnResult> {
  return sendMessageWithTimeoutContinuationInternal(threadId, text, true, runtimeOptions);
}

export async function sendMessageWithoutResumeWithTimeoutContinuation(
  threadId: string,
  text: string,
  runtimeOptions?: TurnRuntimeOptions
): Promise<TimedTurnResult> {
  return sendMessageWithTimeoutContinuationInternal(threadId, text, false, runtimeOptions);
}

export async function createAndSendFirstMessageWithTimeoutContinuation(
  options: ConversationOptions,
  text: string,
  runtimeOptions?: TurnRuntimeOptions
): Promise<TimedCreateTurnResult> {
  return withTurnClient(runtimeOptions, async (client, handOffCompletion) => {
    const threadId = await startThreadOnClient(client, options);
    const timed = await runTurnWithTimeout(
      client,
      threadId,
      text,
      false,
      runtimeOptions?.onTurnEvent
    );

    if (timed.status === "completed") {
      return {
        status: "completed",
        threadId,
        response: timed.response,
      };
    }

    return {
      status: "timed_out",
      threadId,
      completion: handOffCompletion(timed.completion),
    };
  });
}

async function sendMessageWithTimeoutContinuationInternal(
  threadId: string,
  text: string,
  resumeFirst: boolean,
  runtimeOptions?: TurnRuntimeOptions
): Promise<TimedTurnResult> {
  return withTurnClient(runtimeOptions, async (client, handOffCompletion) => {
    const timed = await runTurnWithTimeout(
      client,
      threadId,
      text,
      resumeFirst,
      runtimeOptions?.onTurnEvent
    );

    if (timed.status === "completed") {
      return timed;
    }

    return {
      status: "timed_out",
      completion: handOffCompletion(timed.completion),
    };
  });
}
