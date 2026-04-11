import { JsonRpcNotification } from "./connection.js";
import { asObject, getString, normalizeTextToken } from "./json.js";
import {
  extractCommandText,
  extractDeltaItemType,
  extractDeltaText,
  extractItemOutput,
  extractItemStatus,
  extractItemText,
  isCommandOutputDeltaMethod,
  normalizeItemType,
} from "./turn-event-data.js";
import {
  getTurnFailureMessage,
  latestTurnResponse,
  RunTurnState,
} from "./turn-state.js";

export function handleTurnNotification(state: RunTurnState, notification: JsonRpcNotification): void {
  const params = asObject(notification.params);
  if (!shouldHandleNotification(state, params)) {
    return;
  }

  switch (notification.method) {
    case "turn/started":
      handleTurnStartedNotification(state, params);
      return;
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

function shouldHandleNotification(state: RunTurnState, params: Record<string, unknown>): boolean {
  return isTurnNotificationForThread(state, params) && isTurnNotificationForCurrentTurn(state, params);
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

function handleTurnStartedNotification(state: RunTurnState, params: Record<string, unknown>): void {
  const turn = asObject(params.turn);
  const turnId = getString(turn.id);
  if (turnId) {
    state.currentTurnId = turnId;
  }
}

function handleItemStartedNotification(state: RunTurnState, params: Record<string, unknown>): void {
  const item = asObject(params.item);
  state.emitTurnEvent({
    kind: "itemStarted",
    threadId: state.threadId,
    turnId: state.currentTurnId!,
    itemId: getString(item.id) ?? getString(params.itemId) ?? "unknown-item",
    itemType: normalizeItemType(getString(item.type)),
    command: extractCommandText(item),
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
    text: delta,
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
    text: delta,
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
    output: extractItemOutput(item),
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
    const response = latestTurnResponse(state);
    if (response) {
      state.finalizeSuccess(response);
    } else {
      state.finalizeFailure(new Error("Turn was interrupted before producing a response."));
    }
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
