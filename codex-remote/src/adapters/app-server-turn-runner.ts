import {
  TURN_TIMEOUT_MS,
  TurnProgressEvent,
} from "./app-server-client-types.js";
import { AppServerConnection, JsonRpcNotification } from "./app-server-connection.js";
import { asObject, getString, normalizeTextToken } from "./app-server-json.js";

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
      response: raced.value
    };
  }

  return {
    status: "timed_out",
    completion: completion.then((response) => ({ response }))
  };
}

type RunTurnState = {
  threadId: string;
  currentTurnId: string | null;
  lastAgentMessage: string;
  lastFinalAgentMessage: string;
  agentSnapshots: Map<string, string>;
  emitTurnEvent: (event: TurnProgressEvent) => void;
  finalizeSuccess: (value: string) => void;
  finalizeFailure: (error: unknown) => void;
};

async function runTurn(
  client: AppServerConnection,
  threadId: string,
  text: string,
  resumeFirst: boolean,
  onTurnEvent?: (event: TurnProgressEvent) => void
): Promise<string> {
  if (resumeFirst) {
    await client.send("thread/resume", {
      threadId
    });
  }

  let finished = false;
  let resolveTurn: (value: string) => void = () => {};
  let rejectTurn: (reason: unknown) => void = () => {};
  const turnDone = new Promise<string>((resolve, reject) => {
    resolveTurn = resolve;
    rejectTurn = reject;
  });

  const state: RunTurnState = {
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
    }
  };

  const detachNotification = client.onNotification((notification) => {
    handleTurnNotification(state, notification);
  });

  try {
    const started = await client.send("turn/start", {
      threadId,
      input: [
        {
          type: "text",
          text
        }
      ]
    });

    const startedTurn = asObject(asObject(started).turn);
    state.currentTurnId = getString(startedTurn.id);

    const status = getString(startedTurn.status);
    if (status === "completed") {
      return latestTurnResponse(state);
    }
    if (status === "failed") {
      throw new Error(getTurnFailureMessage(startedTurn));
    }
    if (status === "interrupted") {
      throw new Error("Turn was interrupted before completion.");
    }
    if (status && status !== "inProgress") {
      throw new Error(`Turn started with unexpected status: ${status}`);
    }

    return await turnDone;
  } finally {
    detachNotification();
  }
}

function handleTurnNotification(state: RunTurnState, notification: JsonRpcNotification): void {
  const params = asObject(notification.params);
  if (!isTurnNotificationForThread(state, params)) {
    return;
  }
  if (!isTurnNotificationForCurrentTurn(state, params)) {
    return;
  }

  switch (notification.method) {
    case "turn/started": {
      const turn = asObject(params.turn);
      const turnId = getString(turn.id);
      if (turnId) {
        state.currentTurnId = turnId;
      }
      return;
    }
    case "item/started":
      handleItemStartedNotification(state, params);
      return;
    case "item/agentMessage/delta":
      handleAgentDeltaNotification(state, params);
      return;
    case "item/completed":
      handleItemCompletedNotification(state, params);
      return;
    case "turn/completed":
      handleTurnCompletedNotification(state, params);
      return;
    default:
      handleOutputDeltaNotification(state, notification.method, params);
  }
}

function isTurnNotificationForThread(state: RunTurnState, params: Record<string, unknown>): boolean {
  const eventThreadId = getString(params.threadId) ?? getString(params.conversationId);
  return eventThreadId === state.threadId;
}

function isTurnNotificationForCurrentTurn(state: RunTurnState, params: Record<string, unknown>): boolean {
  const eventTurnId = getString(params.turnId);
  if (!state.currentTurnId && eventTurnId) {
    state.currentTurnId = eventTurnId;
  }
  return !!state.currentTurnId && (!eventTurnId || eventTurnId === state.currentTurnId);
}

function handleItemStartedNotification(state: RunTurnState, params: Record<string, unknown>): void {
  const item = asObject(params.item);
  state.emitTurnEvent({
    kind: "itemStarted",
    threadId: state.threadId,
    turnId: state.currentTurnId!,
    itemId: getString(item.id) ?? getString(params.itemId) ?? "unknown-item",
    itemType: normalizeItemType(getString(item.type)),
    command: extractCommandText(item)
  });
}

function handleAgentDeltaNotification(state: RunTurnState, params: Record<string, unknown>): void {
  const delta = getString(params.delta);
  if (!delta) {
    return;
  }

  const itemId = getString(params.itemId) ?? "agent-message";
  const nextSnapshot = (state.agentSnapshots.get(itemId) ?? "") + delta;
  state.agentSnapshots.set(itemId, nextSnapshot);
  state.lastAgentMessage = nextSnapshot;
  state.emitTurnEvent({
    kind: "agentDelta",
    threadId: state.threadId,
    turnId: state.currentTurnId!,
    itemId,
    itemType: "agentMessage",
    text: delta
  });
}

function handleOutputDeltaNotification(
  state: RunTurnState,
  method: string,
  params: Record<string, unknown>
): void {
  if (!isCommandOutputDeltaMethod(method)) {
    return;
  }

  const delta = extractDeltaText(params);
  if (!delta) {
    return;
  }

  state.emitTurnEvent({
    kind: "commandOutputDelta",
    threadId: state.threadId,
    turnId: state.currentTurnId!,
    itemId: getString(params.itemId) ?? "unknown-item",
    itemType: extractDeltaItemType(method),
    text: delta
  });
}

function handleItemCompletedNotification(state: RunTurnState, params: Record<string, unknown>): void {
  const item = asObject(params.item);
  const itemId = getString(item.id) ?? getString(params.itemId) ?? "unknown-item";
  const itemType = normalizeItemType(getString(item.type));
  const text = extractItemText(item);

  if (itemType === "agentMessage" && text !== null) {
    state.lastAgentMessage = text;
    state.agentSnapshots.set(itemId, text);
    const phase = normalizeTextToken(getString(item.phase));
    if (phase === "finalanswer" || phase === "final") {
      state.lastFinalAgentMessage = text;
    }
  }

  state.emitTurnEvent({
    kind: "itemCompleted",
    threadId: state.threadId,
    turnId: state.currentTurnId!,
    itemId,
    itemType,
    text,
    status: extractItemStatus(item),
    command: extractCommandText(item),
    output: extractItemOutput(item)
  });
}

function handleTurnCompletedNotification(state: RunTurnState, params: Record<string, unknown>): void {
  const turn = asObject(params.turn);
  const completedTurnId = getString(turn.id);
  if (!state.currentTurnId || !completedTurnId || completedTurnId !== state.currentTurnId) {
    return;
  }

  const status = getString(turn.status);
  if (status === "completed") {
    state.finalizeSuccess(latestTurnResponse(state));
    return;
  }

  if (status === "interrupted") {
    const trimmed = latestTurnResponse(state);
    if (trimmed) {
      state.finalizeSuccess(trimmed);
      return;
    }
    state.finalizeFailure(new Error("Turn was interrupted before producing a response."));
    return;
  }

  if (status === "failed") {
    state.finalizeFailure(new Error(getTurnFailureMessage(turn)));
    return;
  }

  if (status === "inProgress") {
    return;
  }

  state.finalizeFailure(new Error(`Turn ended with unexpected status: ${status ?? "unknown"}`));
}

function latestTurnResponse(state: RunTurnState): string {
  return (state.lastFinalAgentMessage || state.lastAgentMessage).trim();
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

function getTurnFailureMessage(turn: Record<string, unknown>): string {
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

function isCommandOutputDeltaMethod(method: string): boolean {
  return (
    method === "item/fileChange/outputDelta" ||
    method === "item/commandExecution/outputDelta" ||
    method === "command/exec/outputDelta"
  );
}

function extractDeltaItemType(method: string): string {
  if (method === "item/fileChange/outputDelta") {
    return "fileChange";
  }
  if (method === "item/commandExecution/outputDelta" || method === "command/exec/outputDelta") {
    return "commandExecution";
  }
  return "unknown";
}

function extractDeltaText(params: Record<string, unknown>): string | null {
  return (
    getString(params.delta) ??
    getString(params.textDelta) ??
    getString(params.summaryTextDelta) ??
    getString(params.outputDelta) ??
    getString(params.text)
  );
}

function normalizeItemType(type: string | null): string {
  if (!type) {
    return "unknown";
  }
  const token = normalizeTextToken(type);
  switch (token) {
    case "agentmessage":
      return "agentMessage";
    case "usermessage":
      return "userMessage";
    case "reasoning":
      return "reasoning";
    case "plan":
      return "plan";
    case "commandexecution":
      return "commandExecution";
    case "filechange":
      return "fileChange";
    case "toolcall":
      return "toolCall";
    case "toolresult":
      return "toolResult";
    case "collabtoolcall":
      return "collabToolCall";
    default:
      return type;
  }
}

function extractItemStatus(item: Record<string, unknown>): string | null {
  const statusValue = item.status;
  if (typeof statusValue === "string") {
    return statusValue;
  }
  return getString(asObject(statusValue).type);
}

function extractCommandText(item: Record<string, unknown>): string | null {
  return getString(item.command);
}

function extractItemOutput(item: Record<string, unknown>): string | null {
  return getString(item.aggregatedOutput) ?? getString(item.aggregated_output) ?? getString(item.output);
}

function extractItemText(item: Record<string, unknown>): string | null {
  return getString(item.text) ?? getString(item.summary);
}
