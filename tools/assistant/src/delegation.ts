import type { Context } from "@earendil-works/chord";
import { AssistantEntry, configure, defineDoc, defineTool, LiveDoc,
  type ConversationId, type Extension, type Harness, type SubmissionId, type TaskId } from "@earendil-works/pi-durable";
import { Type } from "typebox";
import { assistantText } from "./state.ts";

type Role = "researcher" | "reviewer";
type Delegation = { conversationId: number; runId: number; role: Role; submissionId?: number };
const DelegationsDoc = defineDoc<{ calls: Record<string, Delegation> }>({ kind: "assistant.delegations", version: 1,
  scope: "conversation", history: "latest", fork: "initial", initial: () => ({ calls: {} }) });

export function createDelegation(getRole: (role: Role) => Extension, getHarness: () => Harness) {
  async function collect(delegationId: string, child: Delegation, context: Context) {
    const harness = getHarness();
    const submission = child.submissionId === undefined ? undefined : await harness.submission(child.submissionId as SubmissionId, context);
    if (!submission) throw new Error("Delegation was not admitted");
    const result = await submission.wait(context);
    const conversation = (await harness.conversation(child.conversationId as ConversationId, context))!;
    await conversation.waitForIdle(context);
    const details = { delegationId, conversationId: child.conversationId, role: child.role };
    if (result.status !== "done" || result.type !== "input")
      return { ...details, status: "failed", error: result.status === "unanswered" ? result.detail || result.reason : "Worker returned no answer" };
    const answer = await harness.commit((tx) => tx.entry(AssistantEntry, result.answer), context);
    const text = assistantText(answer?.model?.[0] || {});
    return text ? { ...details, status: "done", text } : { ...details, status: "failed", error: "Worker returned no answer" };
  }

  const delegate = defineTool({ name: "delegate",
    description: "Start a read-only researcher or reviewer and immediately return its delegationId. Supply a focused task and context. Continue independent work, then call delegate_result before finishing.",
    parameters: Type.Object({ role: Type.Union([Type.Literal("researcher"), Type.Literal("reviewer")]), task: Type.String({ minLength: 1 }) }), replay: "safe",
    execute: async (args, api, context) => {
      const delegationId = String(api.taskId);
      const child = await api.commit(async (tx) => {
        const saved = await tx.doc(DelegationsDoc, api.conversationId);
        if (saved.calls[delegationId]) return { ...saved.calls[delegationId] };
        const run = (await tx.doc(LiveDoc, api.conversationId)).run;
        if (!run) throw new Error("Delegation requires an active parent request");
        // The generation owns the child so this tool can finish while the child keeps working.
        const created = await tx.createConversation({ ownership: { kind: "task", taskId: run.taskId } });
        await configure(tx, created.id, { extensions: [getRole(args.role)], tools: null, instructions: null });
        const record = { conversationId: created.id, runId: run.taskId, role: args.role };
        saved.calls[delegationId] = record;
        return record;
      }, context);
      const handle = (await api.conversation(child.conversationId as ConversationId, context))!;
      const submission = await handle.submit({ type: "input", content: args.task, requestId: `delegate:${delegationId}` }, context);
      await api.commit(async (tx) => { (await tx.doc(DelegationsDoc, api.conversationId)).calls[delegationId].submissionId = submission.id; }, context);
      const details = { delegationId, conversationId: child.conversationId, role: child.role, status: "started" };
      return { content: [{ type: "text", text: JSON.stringify(details) }], details };
    } });

  const result = defineTool({ name: "delegate_result",
    description: "Collect a delegation from this conversation. Waits for completion without polling and returns its findings or failure. Call when you need the findings or before your final answer.",
    parameters: Type.Object({ delegationId: Type.String({ minLength: 1 }) }), replay: "safe",
    execute: async (args, api, context) => {
      const child = (await api.snapshot(DelegationsDoc, api.conversationId, context))?.calls[args.delegationId];
      if (!child) throw new Error("Delegation not found in this conversation");
      const findings = await collect(args.delegationId, child, context);
      return { content: [{ type: "text", text: JSON.stringify(findings) }], isError: findings.status === "failed",
        details: { delegationId: args.delegationId, conversationId: child.conversationId, role: child.role, status: findings.status } };
    } });

  return [delegate, result];
}

// Pi hands a request to successor generation tasks between tool rounds. Join children
// through their original owners as well as the currently active generation when stopping.
export async function cancelDelegations(harness: Harness, conversationId: ConversationId, context: Context) {
  const calls = (await harness.snapshot(DelegationsDoc, conversationId, context))?.calls || {};
  const owners = [...new Set(Object.values(calls).map(child => child.runId))];
  const tasks = await Promise.all(owners.map(id => harness.getTask(id as TaskId, context)));
  const active = tasks.filter(task => task && task.state.status !== "terminal");
  await Promise.all(active.map(task => harness.abortTask(task!.id, context)));
  await Promise.all(active.map(task => harness.waitForTask(task!.id, context)));
  return active.length > 0;
}
