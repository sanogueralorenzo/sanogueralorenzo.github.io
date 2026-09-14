import type { ThreadGoal } from "../adapters/app-server/generated/v2/ThreadGoal.js";
import type { GoalStatusUpdate } from "../adapters/app-server/client.js";
import type { BindingStore } from "../adapters/binding-store.js";
import { quickActionsKeyboard } from "../bot/keyboards.js";
import { THREAD_NOT_BOUND_MESSAGE } from "../bot/messages.js";
import type { ReplyFn } from "../bot/context.js";

type GoalActionsDeps = {
  store: Pick<BindingStore, "get">;
  getGoal: (threadId: string) => Promise<ThreadGoal | null>;
  setGoalObjective: (threadId: string, objective: string) => Promise<ThreadGoal>;
  setGoalStatus: (threadId: string, status: GoalStatusUpdate) => Promise<ThreadGoal>;
  clearGoal: (threadId: string) => Promise<boolean>;
};

export function createGoalActions(deps: GoalActionsDeps) {
  async function executeGoalCommand(chatId: string, input: string, reply: ReplyFn): Promise<void> {
    const threadId = await deps.store.get(chatId);
    if (!threadId) {
      await reply(THREAD_NOT_BOUND_MESSAGE, { reply_markup: quickActionsKeyboard() });
      return;
    }

    const command = parseGoalCommand(input);
    switch (command.type) {
      case "show":
        await replyCurrentGoal(threadId, reply);
        return;
      case "clear":
        await replyClearedGoal(threadId, reply);
        return;
      case "pause":
        await replyGoalStatusUpdate(threadId, "paused", reply);
        return;
      case "resume":
        await replyGoalStatusUpdate(threadId, "active", reply);
        return;
      case "set": {
        const goal = await deps.setGoalObjective(threadId, command.objective);
        await reply(`Goal set:\n${goal.objective}`);
      }
    }
  }

  async function replyCurrentGoal(threadId: string, reply: ReplyFn): Promise<void> {
    const goal = await deps.getGoal(threadId);
    await reply(goal ? formatGoal(goal) : "No goal set.");
  }

  async function replyClearedGoal(threadId: string, reply: ReplyFn): Promise<void> {
    const cleared = await deps.clearGoal(threadId);
    await reply(cleared ? "Goal cleared." : "No goal set.");
  }

  async function replyGoalStatusUpdate(threadId: string, status: GoalStatusUpdate, reply: ReplyFn): Promise<void> {
    const currentGoal = await deps.getGoal(threadId);
    if (!currentGoal) {
      await reply("No goal set.");
      return;
    }

    const goal = await deps.setGoalStatus(threadId, status);
    await reply(formatStatusUpdate(goal));
  }

  return {
    executeGoalCommand,
  };
}

type ParsedGoalCommand =
  | { type: "show" }
  | { type: "clear" }
  | { type: "pause" }
  | { type: "resume" }
  | { type: "set"; objective: string };

function parseGoalCommand(input: string): ParsedGoalCommand {
  const trimmed = input.trim();
  if (!trimmed) {
    return { type: "show" };
  }

  const normalized = trimmed.toLowerCase();
  if (normalized === "clear") {
    return { type: "clear" };
  }
  if (normalized === "pause") {
    return { type: "pause" };
  }
  if (normalized === "resume") {
    return { type: "resume" };
  }

  return { type: "set", objective: trimmed };
}

function formatGoal(goal: ThreadGoal): string {
  return [`Goal: ${goal.objective}`, `Status: ${goal.status}`].join("\n");
}

function formatStatusUpdate(goal: ThreadGoal): string {
  const action = goal.status === "paused" ? "Goal paused" : "Goal resumed";
  return `${action}:\n${goal.objective}`;
}
