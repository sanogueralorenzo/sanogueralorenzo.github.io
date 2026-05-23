import type { JsonRpcNotification } from "./connection.js";
import type { ThreadItem } from "./generated/v2/ThreadItem.js";
import {
  getTurnFailureMessage,
  latestTurnResponse,
  RunTurnState,
} from "./turn-state.js";

export function handleTurnNotification(state: RunTurnState, notification: JsonRpcNotification): void {
  switch (notification.method) {
    case "turn/started": {
      if (notification.params.threadId === state.threadId) {
        state.currentTurnId = notification.params.turn.id;
      }
      return;
    }
    case "item/started": {
      const { params } = notification;
      if (!isCurrentTurnNotification(state, params.threadId, params.turnId)) {
        return;
      }
      state.emitTurnEvent({
        kind: "itemStarted",
        threadId: state.threadId,
        turnId: params.turnId,
        itemId: params.item.id,
        itemType: params.item.type,
        command: itemCommand(params.item),
      });
      return;
    }
    case "item/agentMessage/delta": {
      const { params } = notification;
      if (!isCurrentTurnNotification(state, params.threadId, params.turnId)) {
        return;
      }
      const nextSnapshot = (state.agentSnapshots.get(params.itemId) ?? "") + params.delta;
      state.agentSnapshots.set(params.itemId, nextSnapshot);
      state.lastAgentMessage = nextSnapshot;
      state.emitTurnEvent({
        kind: "agentDelta",
        threadId: state.threadId,
        turnId: params.turnId,
        itemId: params.itemId,
        itemType: "agentMessage",
        text: params.delta,
      });
      return;
    }
    case "item/commandExecution/outputDelta": {
      const { params } = notification;
      if (!isCurrentTurnNotification(state, params.threadId, params.turnId)) {
        return;
      }
      state.emitTurnEvent({
        kind: "commandOutputDelta",
        threadId: state.threadId,
        turnId: params.turnId,
        itemId: params.itemId,
        itemType: "commandExecution",
        text: params.delta,
      });
      return;
    }
    case "item/completed": {
      const { params } = notification;
      if (!isCurrentTurnNotification(state, params.threadId, params.turnId)) {
        return;
      }
      handleCompletedItem(state, params.turnId, params.item);
      return;
    }
    case "turn/diff/updated": {
      const { params } = notification;
      if (!isCurrentTurnNotification(state, params.threadId, params.turnId)) {
        return;
      }
      state.emitTurnEvent({
        kind: "turnDiffUpdated",
        threadId: state.threadId,
        turnId: params.turnId,
        diff: params.diff,
      });
      return;
    }
    case "turn/completed": {
      const { params } = notification;
      if (params.threadId !== state.threadId || params.turn.id !== state.currentTurnId) {
        return;
      }
      switch (params.turn.status) {
        case "completed":
          state.finalizeSuccess(latestTurnResponse(state));
          return;
        case "interrupted": {
          const response = latestTurnResponse(state);
          if (response) {
            state.finalizeSuccess(response);
          } else {
            state.finalizeFailure(new Error("Turn was interrupted before producing a response."));
          }
          return;
        }
        case "failed":
          state.finalizeFailure(new Error(getTurnFailureMessage(params.turn)));
          return;
        case "inProgress":
          return;
      }
    }
  }
}

function isCurrentTurnNotification(state: RunTurnState, threadId: string, turnId: string): boolean {
  if (threadId !== state.threadId) {
    return false;
  }
  if (!state.currentTurnId) {
    state.currentTurnId = turnId;
  }
  return turnId === state.currentTurnId;
}

function handleCompletedItem(state: RunTurnState, turnId: string, item: ThreadItem): void {
  const text = itemText(item);
  if (item.type === "agentMessage") {
    state.lastAgentMessage = item.text;
    state.agentSnapshots.set(item.id, item.text);
    if (item.phase === "final_answer") {
      state.lastFinalAgentMessage = item.text;
    }
  }

  state.emitTurnEvent({
    kind: "itemCompleted",
    threadId: state.threadId,
    turnId,
    itemId: item.id,
    itemType: item.type,
    text,
    status: itemStatus(item),
    command: itemCommand(item),
    output: itemOutput(item),
    exitCode: itemExitCode(item),
    durationMs: itemDurationMs(item),
  });
}

function itemText(item: ThreadItem): string | null {
  switch (item.type) {
    case "agentMessage":
    case "plan":
      return item.text;
    case "reasoning":
      return item.summary.join("\n");
    default:
      return null;
  }
}

function itemStatus(item: ThreadItem): string | null {
  switch (item.type) {
    case "commandExecution":
    case "fileChange":
    case "mcpToolCall":
    case "dynamicToolCall":
    case "collabAgentToolCall":
      return item.status;
    default:
      return null;
  }
}

function itemCommand(item: ThreadItem): string | null {
  return item.type === "commandExecution" ? item.command : null;
}

function itemOutput(item: ThreadItem): string | null {
  return item.type === "commandExecution" ? item.aggregatedOutput : null;
}

function itemExitCode(item: ThreadItem): number | null {
  return item.type === "commandExecution" ? item.exitCode : null;
}

function itemDurationMs(item: ThreadItem): number | null {
  return item.type === "commandExecution" ? item.durationMs : null;
}
