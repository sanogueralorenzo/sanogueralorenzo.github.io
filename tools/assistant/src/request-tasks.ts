import type { Context } from "@earendil-works/chord";
import { BACKGROUND_CONTEXT } from "@earendil-works/chord/context";
import { configure, defineTask, defineTool, UserEntry, type ConversationId, type EntryId, type SubmissionId, type TaskId, type TaskRuntime, type Tx } from "@earendil-works/pi-durable";
import { Type } from "typebox";
import type { Assistant } from "./assistant.ts";
import { HomeDoc, assistantText, type HomeMessage } from "./state.ts";

type DispatchDecision = { action: "start"; dependsOn: string[] } | { action: "revise" | "cancel"; targetId: string };
type WorkState = { phase: "ready" } | { phase: "fork"; entryId: number; cwd: string } | { phase: "execute"; conversationId: number; cwd: string };
type Input = { sourceId: string; sessionId: string };
type Runtime = TaskRuntime<Input, WorkState, null, object>;
const done = () => ({ status: "terminal" as const, outcome: { status: "completed" as const, result: null } });
export const requestsInSession = (app: Assistant, sessionId: string) => app.state.home.messages.filter(message =>
  app.state.home.entries.find(entry => entry.id === message.entryId)?.sessionId === sessionId);

// Application task IDs are message IDs. They stay stable across a stopped task's new execution attempt.
export async function dispatchMessage(app: Assistant, source: HomeMessage, sessionId: string): Promise<DispatchDecision> {
  const earlier = new Set(app.state.home.messages.slice(0, app.state.home.messages.findIndex(message => message.id === source.id)).map(message => message.id));
  const active = app.snapshot().turns.filter(turn => turn.sessionId === sessionId && earlier.has(turn.sourceId!));
  if (!active.length) return { action: "start", dependsOn: [] };
  if (source.mode === "steer") {
    const target = active.find(turn => turn.sourceId === source.editOfId) || active.filter(turn => turn.status === "running").at(-1);
    if (!target) throw new Error("There is no active task to revise");
    return { action: "revise", targetId: target.sourceId! };
  }
  let accepted: DispatchDecision | undefined;
  const choose = defineTool({ name: "dispatch_message", description: "Choose how this message relates to the listed unfinished tasks. Reference only their exact task IDs.",
    parameters: Type.Object({ action: Type.Union([Type.Literal("start"), Type.Literal("revise"), Type.Literal("cancel")]),
      dependsOn: Type.Optional(Type.Array(Type.String())), targetId: Type.Optional(Type.String()) }, { additionalProperties: false }),
    execute: async args => {
      if (accepted) return { output: [{ type: "text" as const, text: "Dispatch decision already accepted" }] };
      try {
        const ids = new Set(active.map(turn => turn.sourceId));
        if (args.action === "start") {
          const dependsOn = [...new Set(args.dependsOn || [])];
          if (dependsOn.some(id => !ids.has(id))) throw new Error("Dependencies must be listed unfinished task IDs");
          accepted = { action: "start", dependsOn };
        } else {
          if (!args.targetId || !ids.has(args.targetId)) throw new Error("Choose a listed unfinished target task ID");
          if (args.dependsOn?.length) throw new Error("Revisions and cancellations cannot add dependencies");
          accepted = { action: args.action, targetId: args.targetId };
        }
        return { output: [{ type: "text" as const, text: "Dispatch decision accepted" }] };
      } catch (error) { return { output: [{ type: "text" as const, text: String(error) }], isError: true }; }
    } });
  const record = app.state.home.sessions.find(item => item.id === sessionId)!;
  await app.pi.utility("dispatcher", JSON.stringify({
    recent: app.state.transcript(sessionId).slice(-12),
    tasks: active.map(turn => ({ taskId: turn.sourceId, text: turn.text, status: turn.status,
      dependsOn: app.state.home.messages.find(item => item.id === turn.sourceId)?.dependsOn || [] })),
    message: source.prompt || source.text,
  }), record.cwd, [choose], () => accepted ? JSON.stringify(accepted) : undefined);
  if (!accepted) throw new Error("Dispatcher did not choose a task relationship");
  return accepted;
}

export function requestTask(getApp: () => Assistant) {
  async function fail(runtime: Runtime, sourceId: string, error: unknown, context: Context) {
    if (context.abortSignal?.aborted) throw error;
    const message = error instanceof Error ? error.message : String(error);
    await runtime.commit(async tx => {
      const source = (await tx.doc(HomeDoc)).messages.find(item => item.id === sourceId);
      if (source?.submissionId !== undefined) tx.settleSubmission(source.submissionId as SubmissionId, { status: "unanswered", reason: "failed", detail: message });
      return { status: "terminal", outcome: { status: "failed", error: { message } } };
    }, context);
  }
  return defineTask<Input, WorkState, null>({ name: "assistant.request", version: 1, initial: () => ({ phase: "ready" }), phases: {
    ready: async (task, runtime, context) => {
      try {
        await runtime.commit(async tx => {
          const home = await tx.doc(HomeDoc);
          const current = home.messages.find(item => item.id === task.input.sourceId);
          if (!current) return done();
          const session = home.sessions.find(item => item.id === task.input.sessionId)!;
          if (session.paused || current.withdrawn || current.replacedBy) return done();
          const waiting: TaskId[] = [];
          if (current.waitForRunId !== undefined) {
            const replaced = await tx.task(current.waitForRunId as TaskId);
            if (replaced && replaced.state.status !== "terminal") waiting.push(replaced.id);
          }
          // Read the dependency graph and its receipts on the commit line. A concurrent revision cannot change
          // the edges between checking prerequisites and starting this task.
          for (const id of current.dependsOn || []) {
            const dependency = home.messages.find(item => item.id === id);
            if (!dependency) throw new Error(`Prerequisite task ${id} was removed`);
            const receipt = await tx.submissionByRequest(session.conversationId as ConversationId, dependency.requestId || dependency.id);
            if (receipt?.status === "done") continue;
            if (receipt?.status === "unanswered") throw new Error(`Prerequisite task ${id} did not complete: ${receipt.detail || receipt.reason}`);
            if (dependency.workTaskId === undefined) throw new Error(`Prerequisite task ${id} has no execution`);
            const previous = await tx.task(dependency.workTaskId as TaskId);
            if (!previous || previous.state.status === "terminal") throw new Error(`Prerequisite task ${id} did not produce a result`);
            waiting.push(previous.id);
          }
          if (waiting.length) return { status: "waiting", checkpoint: { phase: "ready" }, on: [...new Set(waiting)], policy: "allSettled" };
          const input = await tx.appendEntry(UserEntry, session.conversationId as ConversationId, { model: [{ role: "user", content: current.prompt || current.text, timestamp: Date.now() }] });
          tx.placeSubmission(current.submissionId as SubmissionId, input.id);
          return { status: "running", checkpoint: { phase: "fork", entryId: input.id, cwd: session.cwd } };
        }, context);
      } catch (error) { await fail(runtime, task.input.sourceId, error, context); }
    },
    fork: async (task, runtime, context) => {
      try {
        await runtime.commit(async tx => {
          const home = await tx.doc(HomeDoc);
          const source = home.messages.find(item => item.id === task.input.sourceId)!;
          const record = home.sessions.find(item => item.id === task.input.sessionId)!;
          if (source.replacedBy || source.withdrawn || record.paused) {
            tx.settleSubmission(source.submissionId as SubmissionId, { status: "unanswered", reason: source.replacedBy ? "superseded" : "aborted" });
            return done();
          }
          // Fork only committed history; the input was placed in the previous durable phase.
          const execution = await tx.forkConversation(record.conversationId as ConversationId, task.state.checkpoint.entryId as EntryId,
            { ownership: { kind: "task", taskId: runtime.taskId } });
          source.executionId = execution.id;
          return { status: "running", checkpoint: { phase: "execute", conversationId: execution.id, cwd: task.state.checkpoint.cwd } };
        }, context);
      } catch (error) { await fail(runtime, task.input.sourceId, error, context); }
    },
    execute: async (task, runtime, context) => {
      const app = getApp();
      try {
        const source = app.state.home.messages.find(item => item.id === task.input.sourceId)!;
        const execution = (await runtime.conversation(task.state.checkpoint.conversationId as ConversationId, context))!;
        await app.state.observe(execution.id);
        const submission = await execution.submit({ type: "input", requestId: `execute:${source.requestId || source.id}`,
          content: `Execute only the assigned user request below. Earlier unfinished requests in the history belong to other tasks; do not execute or assume their results. Required prerequisites have completed and their answers are in the history. Plan and delegate within this task as needed, verify the result, and return the final answer for this request.\n\n${source.prompt || source.text}` }, context);
        // This invocation waits without occupying a model slot or the visible conversation. The saved phase and
        // request ID resume the same submission after restart; completion atomically publishes one result event.
        const result = await submission.wait(context);
        await execution.waitForIdle(context);
        if (result.status !== "done" || result.type !== "input") throw new Error(result.status === "unanswered" ? String(result.detail || result.reason) : "Task returned no answer");
        const answer = await app.pi.harness.commit(tx => tx.entry(result.answer), context);
        const message = answer?.model?.[0];
        if (message?.role !== "assistant" || !assistantText(message)) throw new Error("Task returned no final reply");
        const conversation = (await app.pi.harness.conversation(execution.id, context))!;
        const agent = await conversation.agent(context);
        await runtime.commit(async tx => {
          const home = await tx.doc(HomeDoc);
          const current = home.messages.find(item => item.id === source.id)!;
          const record = home.sessions.find(item => item.id === task.input.sessionId)!;
          const receipt = await tx.submissionByRequest(record.conversationId as ConversationId, current.requestId || current.id);
          if (receipt?.status !== "placed") return done();
          if (current.replacedBy || record.paused) {
            tx.settleSubmission(receipt.id, { status: "unanswered", reason: current.replacedBy ? "superseded" : "aborted", detail: current.replacedBy ? "Replaced by a newer request" : "Stopped" });
            return done();
          }
          const published = await tx.appendEntry(record.conversationId as ConversationId, { kind: "assistant.result", data: { sourceId: source.id, taskId: runtime.taskId },
            model: [{ ...message, timestamp: Date.now(), content: message.content.filter(part => part.type === "text") }] });
          tx.settleSubmission(receipt.id, { status: "done", answer: published.id });
          if (agent.cwd && agent.cwd !== task.state.checkpoint.cwd && record.cwd === task.state.checkpoint.cwd) {
            record.cwd = agent.cwd;
            await configure(tx, record.conversationId as ConversationId, { cwd: agent.cwd });
          }
          return done();
        }, context);
      } catch (error) { await fail(runtime, task.input.sourceId, error, context); }
      finally { await app.state.forget(task.state.checkpoint.conversationId); }
    },
  }, abort: async (task, runtime, context) => {
    await runtime.commit(async tx => {
      const home = await tx.doc(HomeDoc);
      const source = home.messages.find(item => item.id === task.input.sourceId);
      const session = home.sessions.find(item => item.id === task.input.sessionId);
      const receipt = source && session && await tx.submissionByRequest(session.conversationId as ConversationId, source.requestId || source.id);
      // Stop preserves tasks that have not started; Continue recreates their execution attempts together.
      if (receipt && !(receipt.status === "queued" && session?.paused)) tx.settleSubmission(receipt.id, { status: "unanswered", reason: source?.replacedBy ? "superseded" : "aborted", ...(source?.replacedBy && { detail: "Replaced by a newer request" }) });
      return { status: "terminal", outcome: { status: "aborted" } };
    }, context);
  } });
}

export async function enqueueRequest(tx: Tx, work: ReturnType<typeof requestTask>, source: HomeMessage, sessionId: string) {
  const home = await tx.doc(HomeDoc);
  const record = home.sessions.find(item => item.id === sessionId)!;
  const receipt = await tx.createSubmission({ conversationId: record.conversationId as ConversationId, type: "input", status: "queued", requestId: source.requestId || source.id });
  source.submissionId = receipt.id;
  if (!record.paused) source.workTaskId = await tx.createTask(work, { sourceId: source.id, sessionId }, { conversationId: record.conversationId as ConversationId, ownership: { kind: "conversation" } });
}

export async function cancelRequest(app: Assistant, sourceId: string) {
  const source = app.state.home.messages.find(item => item.id === sourceId);
  if (source?.workTaskId === undefined) return;
  await app.pi.harness.abortTask(source.workTaskId as TaskId, BACKGROUND_CONTEXT);
  await app.pi.harness.waitForTask(source.workTaskId as TaskId, BACKGROUND_CONTEXT);
}

