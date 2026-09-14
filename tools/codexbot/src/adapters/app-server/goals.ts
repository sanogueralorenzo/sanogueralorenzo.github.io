import type { ThreadGoal } from "./generated/v2/ThreadGoal.js";
import type { ThreadGoalClearResponse } from "./generated/v2/ThreadGoalClearResponse.js";
import type { ThreadGoalGetResponse } from "./generated/v2/ThreadGoalGetResponse.js";
import type { ThreadGoalSetResponse } from "./generated/v2/ThreadGoalSetResponse.js";
import type { ThreadGoalStatus } from "./generated/v2/ThreadGoalStatus.js";
import { withAppServer } from "./connection.js";

export type GoalStatusUpdate = Extract<ThreadGoalStatus, "active" | "paused">;

export async function getThreadGoal(threadId: string): Promise<ThreadGoal | null> {
  return withAppServer(async (client) => {
    const result = await client.send("thread/goal/get", { threadId });
    return (result as ThreadGoalGetResponse).goal ?? null;
  });
}

export async function setThreadGoalObjective(threadId: string, objective: string): Promise<ThreadGoal> {
  return withAppServer(async (client) => {
    const result = await client.send("thread/goal/set", {
      threadId,
      objective,
      status: "active",
    });
    return getSetGoalResult(result);
  });
}

export async function setThreadGoalStatus(threadId: string, status: GoalStatusUpdate): Promise<ThreadGoal> {
  return withAppServer(async (client) => {
    const result = await client.send("thread/goal/set", { threadId, status });
    return getSetGoalResult(result);
  });
}

export async function clearThreadGoal(threadId: string): Promise<boolean> {
  return withAppServer(async (client) => {
    const result = await client.send("thread/goal/clear", { threadId });
    return (result as ThreadGoalClearResponse).cleared === true;
  });
}

function getSetGoalResult(result: unknown): ThreadGoal {
  const goal = (result as ThreadGoalSetResponse).goal;
  if (!goal) {
    throw new Error("app-server thread/goal/set did not return a goal");
  }
  return goal;
}
