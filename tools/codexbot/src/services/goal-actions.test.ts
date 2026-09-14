import type { ThreadGoal } from "../adapters/app-server/generated/v2/ThreadGoal.js";
import { describe, expect, it, vi } from "vitest";
import { createGoalActions } from "./goal-actions.js";

function goal(overrides: Partial<ThreadGoal> = {}): ThreadGoal {
  return {
    threadId: "thread-1",
    objective: "ship the bridge",
    status: "active",
    tokenBudget: null,
    tokensUsed: 0,
    timeUsedSeconds: 0,
    createdAt: 1,
    updatedAt: 1,
    ...overrides,
  };
}

function setup(boundThreadId: string | null = "thread-1") {
  const replies: string[] = [];
  const deps = {
    store: {
      get: vi.fn(async () => boundThreadId),
    },
    getGoal: vi.fn(async () => goal()),
    setGoalObjective: vi.fn(async (_threadId: string, objective: string) => goal({ objective })),
    setGoalStatus: vi.fn(async (_threadId: string, status: "active" | "paused") => goal({ status })),
    clearGoal: vi.fn(async () => true),
  };
  const actions = createGoalActions(deps);
  const reply = vi.fn(async (text: string) => {
    replies.push(text);
  });

  return { actions, deps, replies, reply };
}

describe("createGoalActions", () => {
  it("shows the current goal when no payload is provided", async () => {
    const { actions, deps, replies, reply } = setup();

    await actions.executeGoalCommand("123", "", reply);

    expect(deps.getGoal).toHaveBeenCalledWith("thread-1");
    expect(replies).toEqual(["Goal: ship the bridge\nStatus: active"]);
  });

  it("sets a new active goal from the payload", async () => {
    const { actions, deps, replies, reply } = setup();

    await actions.executeGoalCommand("123", "review the PR", reply);

    expect(deps.setGoalObjective).toHaveBeenCalledWith("thread-1", "review the PR");
    expect(replies).toEqual(["Goal set:\nreview the PR"]);
  });

  it("pauses and resumes only when a goal exists", async () => {
    const { actions, deps, replies, reply } = setup();

    await actions.executeGoalCommand("123", "pause", reply);
    await actions.executeGoalCommand("123", "resume", reply);

    expect(deps.setGoalStatus).toHaveBeenNthCalledWith(1, "thread-1", "paused");
    expect(deps.setGoalStatus).toHaveBeenNthCalledWith(2, "thread-1", "active");
    expect(replies).toEqual(["Goal paused:\nship the bridge", "Goal resumed:\nship the bridge"]);
  });

  it("clears the current goal", async () => {
    const { actions, deps, replies, reply } = setup();

    await actions.executeGoalCommand("123", "clear", reply);

    expect(deps.clearGoal).toHaveBeenCalledWith("thread-1");
    expect(replies).toEqual(["Goal cleared."]);
  });

  it("does not call app-server goal APIs when no thread is bound", async () => {
    const { actions, deps, replies, reply } = setup(null);

    await actions.executeGoalCommand("123", "review the PR", reply);

    expect(deps.setGoalObjective).not.toHaveBeenCalled();
    expect(deps.getGoal).not.toHaveBeenCalled();
    expect(replies[0]).toContain("No thread bound.");
  });
});
