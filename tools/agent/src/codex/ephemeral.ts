import { on } from "node:events";
import { UTILITY_MODEL } from "../local/config.js";
import { utilityInstructionsPath, type CodexAppServer } from "./app-server.js";
import { classifiedError, nextForThread, object, type Notifications } from "./notifications.js";

export async function ephemeralToolTurn<T>(input: {
  client: CodexAppServer;
  homeDir: string;
  cwd: string;
  instructions: string;
  prompt: string;
  tools: object[];
  effort: "none" | "low" | "medium" | "high";
  failureMessage: string;
  signal: AbortSignal | undefined;
  onTool: (name: string, args: Record<string, unknown>) => { response: unknown; result?: T };
}): Promise<T | null> {
  const { client, signal } = input;
  if (signal?.aborted) throw new DOMException("Interrupted", "AbortError");
  const started = await client.request<{ thread: { id: string } }>("thread/start", {
    model: UTILITY_MODEL,
    cwd: input.cwd,
    approvalPolicy: "never",
    sandbox: "danger-full-access",
    ephemeral: true,
    threadSource: "appServer",
    dynamicTools: input.tools,
    config: { model_instructions_file: utilityInstructionsPath(input.homeDir) },
    baseInstructions: input.instructions,
  });
  const threadId = started.thread.id;
  const lifetime = new AbortController();
  const queue = on(client, "notification", { signal: lifetime.signal }) as Notifications;
  const abort = () => lifetime.abort();
  signal?.addEventListener("abort", abort, { once: true });
  if (signal?.aborted) abort();
  let turnId = "";
  let completed = false;
  try {
    const turn = await client.request<{ turn: { id: string } }>("turn/start", {
      threadId,
      input: [{ type: "text", text: input.prompt, text_elements: [] }],
      model: UTILITY_MODEL,
      effort: input.effort,
    });
    turnId = turn.turn.id;
    while (true) {
      const { id, method, params } = await nextForThread(queue, threadId);
      const eventTurnId = params.turnId ?? object(params.turn).id;
      if (eventTurnId && eventTurnId !== turnId) continue;
      if (method === "item/tool/call" && id !== undefined) {
        const answer = input.onTool(String(params.tool ?? ""), object(params.arguments));
        client.respond(id, answer.response);
        if (answer.result !== undefined) return answer.result;
      } else if (method === "turn/completed") {
        completed = true;
        const result = object(params.turn);
        if (result.status === "completed") return null;
        if (result.status === "interrupted") throw new DOMException("Interrupted", "AbortError");
        throw classifiedError(object(result.error).message ?? input.failureMessage);
      }
    }
  } finally {
    lifetime.abort();
    signal?.removeEventListener("abort", abort);
    if (turnId && !completed) await client.request("turn/interrupt", { threadId, turnId }).catch(() => undefined);
    await client.request("thread/unsubscribe", { threadId }).catch(() => undefined);
  }
}
