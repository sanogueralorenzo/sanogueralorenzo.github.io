import { describe, expect, it, vi } from "vitest";

import { createRunTurnState } from "./turn-state.js";
import { handleTurnNotification } from "./turn-notifications.js";

describe("handleTurnNotification", () => {
  it("tracks agent deltas and completes with the final response", async () => {
    const onTurnEvent = vi.fn();
    const { state, turnDone } = createRunTurnState("thread-1", onTurnEvent);

    handleTurnNotification(state, {
      method: "turn/started",
      params: {
        threadId: "thread-1",
        turn: { id: "turn-1" },
      },
    });
    handleTurnNotification(state, {
      method: "item/agentMessage/delta",
      params: {
        threadId: "thread-1",
        turnId: "turn-1",
        itemId: "item-1",
        delta: "Hello",
      },
    });
    handleTurnNotification(state, {
      method: "item/completed",
      params: {
        threadId: "thread-1",
        turnId: "turn-1",
        itemId: "item-1",
        item: {
          id: "item-1",
          type: "agent_message",
          phase: "final_answer",
          text: "Hello world",
        },
      },
    });
    handleTurnNotification(state, {
      method: "turn/completed",
      params: {
        threadId: "thread-1",
        turnId: "turn-1",
        turn: {
          id: "turn-1",
          status: "completed",
        },
      },
    });

    await expect(turnDone).resolves.toBe("Hello world");
    expect(onTurnEvent).toHaveBeenCalled();
  });

  it("ignores notifications for a different thread", () => {
    const onTurnEvent = vi.fn();
    const { state } = createRunTurnState("thread-1", onTurnEvent);

    handleTurnNotification(state, {
      method: "item/agentMessage/delta",
      params: {
        threadId: "thread-2",
        itemId: "item-1",
        delta: "Hello",
      },
    });

    expect(onTurnEvent).not.toHaveBeenCalled();
    expect(state.lastAgentMessage).toBe("");
  });
});
