import { homedir } from "node:os";
import { configure, defineTask, type ConversationId, type SubmissionId, type TaskId, type Tx } from "@earendil-works/pi-durable";
import type { Agent } from "./agent.ts";
import type { Route } from "./home-routing.ts";
import { HomeDoc, now, type HomeMessage } from "./state.ts";
import { dispatchMessage, enqueueRequest, cancelRequest } from "./request-tasks.ts";

type RoutingState = { phase: "route" } | { phase: "create"; route: Route };
type DispatchState = { phase: "wait" } | { phase: "dispatch" };
const done = () => ({ status: "terminal" as const, outcome: { status: "completed" as const, result: null } });
const errorText = (error: unknown) => error instanceof Error ? error.message : String(error);

async function failed(tx: Tx, sourceId: string, error: unknown) {
  const source = (await tx.doc(HomeDoc)).messages.find(item => item.id === sourceId);
  if (source) { source.status = "failed"; source.error = errorText(error); }
  return { status: "terminal" as const, outcome: { status: "failed" as const, error: { message: errorText(error) } } };
}

export function routingTask(getApp: () => Agent, dispatch: ReturnType<typeof dispatchTask>) {
  return defineTask<{ sourceId: string; after?: number }, RoutingState, null>({ name: "agent.route", version: 1, initial: () => ({ phase: "route" }), phases: {
    route: async (task, runtime, context) => {
      if (task.input.after !== undefined) {
        const previous = await runtime.getTask(task.input.after as TaskId, context);
        if (previous && previous.state.status !== "terminal") {
          await runtime.commit(() => ({ status: "waiting", checkpoint: { phase: "route" }, on: [previous.id], policy: "allSettled" }), context);
          return;
        }
      }
      const app = getApp();
      const message = app.state.home.messages.find(item => item.id === task.input.sourceId);
      if (!message) { await runtime.commit(done, context); return; }
      try {
        const route = await app.router.discover(message, context);
        await runtime.commit(() => ({ status: "running", checkpoint: { phase: "create", route: JSON.parse(JSON.stringify(route)) } }), context);
      } catch (error) {
        if (context.abortSignal?.aborted) throw error;
        await runtime.commit(tx => failed(tx, task.input.sourceId, error), context);
      }
    },
    create: async (task, runtime, context) => {
      const app = getApp();
      try {
        await runtime.commit(async tx => {
          const home = await tx.doc(HomeDoc);
          const source = home.messages.find(item => item.id === task.input.sourceId);
          if (!source) return done();
          const route = task.state.checkpoint.route;
          let session = route.mode === "continue" ? home.sessions.find(item => item.id === route.sessionId) : undefined;
          if (!session) {
            const cwd = route.mode === "start" ? route.cwd?.trim() || homedir() : app.cwd;
            const created = await tx.createConversation({ ownership: { kind: "ownerless" } });
            await configure(tx, created.id, app.pi.agent("coordinator", cwd));
            const title = route.mode === "start" ? route.title.slice(0, 100).replace(/\x1b\[[0-?]*[ -/]*[@-~]/g, "").replace(/[\x00-\x08\x0b-\x1f\x7f]/g, "") : "Conversation";
            home.sessions.push({ id: String(created.id), conversationId: created.id, title, cwd, paused: false, createdAt: now() });
            session = home.sessions.at(-1)!;
          }
          const entry = home.entries.find(item => item.id === source.entryId)!;
          entry.sessionId = session.id; entry.title = session.title;
          source.status = "routed";
          await enqueueDispatch(tx, dispatch, source, session.id);
          // Publish the destination and handoff atomically before the next Home message routes.
          return done();
        }, context);
      } catch (error) {
        if (context.abortSignal?.aborted) throw error;
        await runtime.commit(tx => failed(tx, task.input.sourceId, error), context);
      }
    },
  }, abort: async (_task, runtime, context) => {
    await runtime.commit(() => ({ status: "terminal", outcome: { status: "aborted" } }), context);
  } });
}

export async function enqueueDispatch(tx: Tx, dispatch: ReturnType<typeof dispatchTask>, source: HomeMessage, sessionId: string) {
  const record = (await tx.doc(HomeDoc)).sessions.find(item => item.id === sessionId)!;
  source.taskId = await tx.createTask(dispatch, { sourceId: source.id, sessionId,
    ...(record.lastDispatchTaskId !== undefined && { after: record.lastDispatchTaskId }) },
    { conversationId: record.conversationId as ConversationId, ownership: { kind: "conversation" } });
  record.lastDispatchTaskId = source.taskId;
}

export function dispatchTask(getApp: () => Agent) {
  return defineTask<{ sourceId: string; sessionId: string; after?: number }, DispatchState, null>({ name: "agent.dispatch", version: 2, initial: () => ({ phase: "wait" }), phases: {
    wait: async (task, runtime, context) => {
      if (task.input.after !== undefined) {
        const previous = await runtime.getTask(task.input.after as TaskId, context);
        if (previous && previous.state.status !== "terminal") {
          await runtime.commit(() => ({ status: "waiting", checkpoint: { phase: "wait" }, on: [previous.id], policy: "allSettled" }), context);
          return;
        }
      }
      await runtime.commit(() => ({ status: "running", checkpoint: { phase: "dispatch" } }), context);
    },
    dispatch: async (task, runtime, context) => {
      const app = getApp();
      const message = app.state.home.messages.find((item) => item.id === task.input.sourceId);
      if (!message) { await runtime.commit(() => ({ status: "terminal", outcome: { status: "completed", result: null } }), context); return; }
      const sessionId = task.input.sessionId;
      const record = app.state.home.sessions.find((item) => item.id === sessionId)!;
      await app.state.observe(record.conversationId);
      try {
        // Only this conversation waits for the decision; execution runs in its own durable task.
        const decision = await runtime.memo<Awaited<ReturnType<typeof dispatchMessage>>>("dispatch-decision", context)
          ?? await runtime.memo("dispatch-decision", await dispatchMessage(app, message, sessionId, context), context);
        await runtime.commit(async tx => {
          const home = await tx.doc(HomeDoc);
          const source = home.messages.find(item => item.id === task.input.sourceId)!;
          if (source.submissionId !== undefined) return undefined;
          source.dependsOn = decision.action === "start" ? decision.dependsOn : [];
          if (decision.action !== "start") {
            const target = home.messages.find(item => item.id === decision.targetId)!;
            const receipt = await tx.submissionByRequest(record.conversationId as ConversationId, target.requestId || target.id);
            const finished = receipt?.status === "done" || receipt?.status === "unanswered";
            if (target.workTaskId !== undefined) source.waitForRunId = target.workTaskId;
            if (decision.action === "revise") {
              for (const dependent of home.messages) if (dependent.dependsOn?.includes(decision.targetId)) {
                const pending = await tx.submissionByRequest(record.conversationId as ConversationId, dependent.requestId || dependent.id);
                if (pending?.status === "queued") dependent.dependsOn = dependent.dependsOn.map(id => id === decision.targetId ? source.id : id);
              }
            }
            if (!finished) {
              target.replacedBy = source.id;
              if (target.submissionId !== undefined) tx.settleSubmission(target.submissionId as SubmissionId, { status: "unanswered", reason: "superseded", detail: "Replaced by a newer request" });
            }
            if (decision.action === "cancel") source.prompt = finished
              ? `The requested task already finished before cancellation was dispatched. Explain briefly; do not claim it was cancelled. Original message: ${source.text}`
              : `The requested task was cancelled. Acknowledge briefly. Original message: ${source.text}`;
          }
          await enqueueRequest(tx, app.work, source, sessionId);
          return undefined;
        }, context);
        if (decision.action !== "start") await cancelRequest(app, decision.targetId);
        await runtime.commit(() => ({ status: "terminal", outcome: { status: "completed", result: null } }), context);
      } catch (error) {
        if (context.abortSignal?.aborted) throw error;
        await runtime.commit(tx => failed(tx, task.input.sourceId, error), context);
      }
    },
  }, abort: async (_task, runtime, context) => {
    await runtime.commit(() => ({ status: "terminal", outcome: { status: "aborted" } }), context);
  } });
}
