import type { Context } from "@earendil-works/chord";
import { AssistantEntry, configure, defineDoc, defineTool, GenerationTask, hook, LiveDoc,
  type ConversationId, type Extension, type Harness, type SubmissionId, type TaskId } from "@earendil-works/pi-durable";
import { Type } from "typebox";
import { agentText } from "./state.ts";

type Status = "outstanding" | "collected" | "failed" | "cancelled";
type Delegation = { conversationId: number; ownerTaskId: number; requestId: number; status: Status; submissionId?: number; reason?: string };
export const DelegationsDoc = defineDoc<{ calls: Record<string, Delegation> }>({ kind: "agent.delegations", version: 2,
  scope: "conversation", history: "latest", fork: "initial", checkpointWhen: () => false, initial: () => ({ calls: {} }) });

export function createDelegation(getWorker: () => Extension, getHarness: () => Harness) {
  async function collect(delegationId: string, child: Delegation, context: Context) {
    const harness = getHarness();
    const submission = child.submissionId === undefined ? undefined : await harness.submission(child.submissionId as SubmissionId, context);
    if (!submission) throw new Error("Delegation was not started");
    const result = await submission.wait(context);
    const conversation = (await harness.conversation(child.conversationId as ConversationId, context))!;
    await conversation.waitForIdle(context);
    const details = { delegationId, conversationId: child.conversationId };
    if (result.status !== "done" || result.type !== "input")
      return { ...details, status: "failed", error: result.status === "unanswered" ? result.detail || result.reason : "Worker returned no answer" };
    const answer = await harness.commit((tx) => tx.entry(AssistantEntry, result.answer), context);
    const text = agentText(answer?.model?.[0] || {});
    return text ? { ...details, status: "done", text } : { ...details, status: "failed", error: "Worker returned no answer" };
  }

  const delegate = defineTool({ name: "delegate",
    description: "Start a worker for a focused task and immediately return its delegationId. The worker has coding, shell, computer-use, and delegation tools and inherits your model and working directory. Supply the goal, relevant context, constraints, resource ownership, and a stopping condition. Continue independent work, then collect with delegate_result or cancel unneeded work with delegate_cancel.",
    parameters: Type.Object({ task: Type.String({ minLength: 1 }) }, { additionalProperties: false }), replay: "safe",
    execute: async (args, api, context) => {
      const delegationId = String(api.taskId);
      const parent = await api.agent(context);
      const child = await api.commit(async (tx) => {
        const saved = await tx.doc(DelegationsDoc, api.conversationId);
        if (saved.calls[delegationId]) return { ...saved.calls[delegationId] };
        const run = (await tx.doc(LiveDoc, api.conversationId)).run;
        if (!run) throw new Error("Delegation requires an active parent request");
        // The generation owns the child so this tool can finish while the child keeps working.
        const created = await tx.createConversation({ ownership: { kind: "task", taskId: run.taskId } });
        const worker = getWorker();
        await configure(tx, created.id, { extensions: [...parent.extensions.filter(extension => extension.name !== "agent-coordinator" && extension.name !== worker.name), worker],
          tools: null, modelTools: null, instructions: null });
        const record: Delegation = { conversationId: created.id, ownerTaskId: run.taskId, requestId: run.inputs[0], status: "outstanding" };
        saved.calls[delegationId] = record;
        return record;
      }, context);
      const handle = (await api.conversation(child.conversationId as ConversationId, context))!;
      const submission = await handle.submit({ type: "input", content: args.task, requestId: `delegate:${delegationId}` }, context);
      await api.commit(async (tx) => { (await tx.doc(DelegationsDoc, api.conversationId)).calls[delegationId].submissionId = submission.id; }, context);
      const details = { delegationId, conversationId: child.conversationId, status: "outstanding" };
      return { output: [{ type: "text", text: JSON.stringify(details) }], details };
    } });

  const result = defineTool({ name: "delegate_result",
    description: "Collect a delegation from this conversation. Waits for completion without polling and returns its findings or failure. Call when you need the findings or before your final answer.",
    parameters: Type.Object({ delegationId: Type.String({ pattern: "^[0-9]+$" }) }, { additionalProperties: false }), replay: "safe",
    execute: async (args, api, context) => {
      const child = (await api.snapshot(DelegationsDoc, api.conversationId, context))?.calls[args.delegationId];
      if (!child) throw new Error("Delegation not found in this conversation");
      if (child.status === "cancelled") return { output: [{ type: "text", text: JSON.stringify({ delegationId: args.delegationId, status: "cancelled", reason: child.reason }) }] };
      const findings = await collect(args.delegationId, child, context);
      await api.commit(async tx => {
        const saved = (await tx.doc(DelegationsDoc, api.conversationId)).calls[args.delegationId];
        if (saved.status !== "cancelled") saved.status = findings.status === "done" ? "collected" : "failed";
      }, context);
      return { output: [{ type: "text", text: JSON.stringify(findings) }], isError: findings.status === "failed",
        details: { delegationId: args.delegationId, conversationId: child.conversationId, status: findings.status } };
    } });

  const cancel = defineTool({ name: "delegate_cancel", replay: "safe",
    description: "Cancel delegated work that is no longer needed. Supply its delegationId and a reason. Waits for the worker to stop before returning.",
    parameters: Type.Object({ delegationId: Type.String({ pattern: "^[0-9]+$" }), reason: Type.String({ minLength: 1 }) }, { additionalProperties: false }),
    execute: async (args, api, context) => {
      const child = (await api.snapshot(DelegationsDoc, api.conversationId, context))?.calls[args.delegationId];
      if (!child) throw new Error("Delegation not found in this conversation");
      if (child.status === "outstanding" || child.status === "cancelled") {
        await api.commit(async tx => {
          const saved = (await tx.doc(DelegationsDoc, api.conversationId)).calls[args.delegationId];
          if (saved.status === "outstanding") { saved.status = "cancelled"; saved.reason = args.reason; }
        }, context);
        await (await api.conversation(child.conversationId as ConversationId, context))!.abort(context);
      }
      const saved = (await api.snapshot(DelegationsDoc, api.conversationId, context))!.calls[args.delegationId];
      const details = { delegationId: args.delegationId, conversationId: child.conversationId, status: saved.status, ...(saved.reason && { reason: saved.reason }) };
      return { output: [{ type: "text", text: JSON.stringify(details) }], details };
    } });

  return [delegate, result, cancel];
}

// Pi hands a request to successor generation tasks between tool rounds. Join children
// through their original owners as well as the currently active generation when stopping.
export async function cancelDelegations(harness: Harness, conversationId: ConversationId, context: Context) {
  const calls = (await harness.snapshot(DelegationsDoc, conversationId, context))?.calls || {};
  const owners = [...new Set(Object.values(calls).filter(child => child.status === "outstanding" || child.status === "cancelled").map(child => child.ownerTaskId))];
  const tasks = await Promise.all(owners.map(id => harness.getTask(id as TaskId, context)));
  const active = tasks.filter(task => task && task.state.status !== "terminal");
  await Promise.all(active.map(task => harness.abortTask(task!.id, context)));
  await Promise.all(active.map(task => harness.waitForTask(task!.id, context)));
  await harness.commit(async tx => {
    for (const child of Object.values((await tx.doc(DelegationsDoc, conversationId)).calls))
      if (child.status === "outstanding") { child.status = "cancelled"; child.reason = "Parent stopped"; }
  }, context);
  return active.length > 0;
}

export const delegationHooks = [hook(GenerationTask, { afterResponse: async (message, api, context) => {
  const final = ["stop", "length", "toolUse"].includes(message.stopReason) &&
    !(message.stopReason === "toolUse" && message.content.some(part => part.type === "toolCall"));
  if (!final) return;
  const requestId = (await api.snapshot(LiveDoc, api.conversationId, context))?.run?.inputs[0];
  const calls = (await api.snapshot(DelegationsDoc, api.conversationId, context))?.calls || {};
  const pending = Object.entries(calls).filter(([, child]) => child.requestId === requestId && child.status === "outstanding");
  if (!pending.length) return;
  // Replace the premature answer with a durable collection round before the final
  // boundary can settle this request or start queued follow-ups.
  message.content = [...message.content.filter(part => part.type === "thinking"),
    ...pending.map(([delegationId]) => ({ type: "toolCall" as const, id: `collect_${api.taskId}_${delegationId}`,
      name: "delegate_result", arguments: { delegationId } }))];
  message.stopReason = "toolUse";
} })];
