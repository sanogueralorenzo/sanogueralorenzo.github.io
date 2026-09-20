import { randomUUID } from "node:crypto";
import { existsSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import type { Response, ResponseInputItem } from "openai/resources/responses/responses";
import { describe, expect, it } from "vitest";
import { BackendRegistry } from "./backend.js";
import type { ModelClient, ModelRequest } from "../openai/model.js";
import { ResponsesBackend } from "../openai/responses-backend.js";
import { AgentRuntime } from "./runtime.js";
import { Store } from "./store.js";
import type { RuntimeConfig, RuntimeEvent } from "./types.js";
import { cleanup, temporary } from "../test-support.js";

function response(id: string, output: Response["output"], outputText = ""): Response {
  return { id, output, output_text: outputText } as Response;
}

function textResponse(id: string, text: string): Response {
  return response(id, [{
    type: "message",
    id: `message-${id}`,
    role: "assistant",
    status: "completed",
    content: [{ type: "output_text", text, annotations: [], logprobs: [] }],
  }], text);
}

type TestModel = ModelClient & { calls: ModelRequest[] };

function testModel(
  reply: (request: ModelRequest, call: number) => Response | Promise<Response>,
  transcribeAudio?: ModelClient["transcribeAudio"],
): TestModel {
  const calls: ModelRequest[] = [];
  return {
    calls,
    async *stream(request) {
      calls.push(request);
      const result = await reply(request, calls.length);
      if (result.output_text) yield { type: "text_delta", delta: result.output_text };
      return result;
    },
    ...(transcribeAudio ? { transcribeAudio } : {}),
  };
}

function routingModel(transcribeAudio?: ModelClient["transcribeAudio"]): TestModel {
  return testModel((request, call) => {
    const worker = request.model !== "gpt-5.6-luna" || /internal (?:Luna worker|Sol|Astra)/.test(request.instructions);
    return textResponse(`${worker ? "worker" : "coordinator"}-${call}`, worker ? "Worker result." : "Combined.");
  }, transcribeAudio);
}

function runtime(homeDir: string, store: Store, model: ModelClient): AgentRuntime {
  const currentConfig: RuntimeConfig = { homeDir, port: 0, codexCommand: "codex" };
  const responses = new ResponsesBackend(currentConfig, store, model);
  store.setSetting("backend", "responses");
  return new AgentRuntime(store, new BackendRegistry(store, responses, responses));
}

function testRuntime(model: ModelClient) {
  const path = temporary("agent-runtime-");
  const store = new Store(path);
  cleanup(() => store.close());
  return { path, store, assistant: runtime(path, store, model) };
}

async function collect(assistant: AgentRuntime, request: Parameters<AgentRuntime["run"]>[0]): Promise<RuntimeEvent[]> {
  const events: RuntimeEvent[] = [];
  for await (const event of assistant.run(request)) events.push(event);
  return events;
}

describe("AgentRuntime", () => {
  it("keeps memory and final synthesis on the persistent Luna-high coordinator", async () => {
    const model = testModel((_request, call) => call === 1
      ? response("first", [{
        type: "function_call", call_id: "call-1", name: "remember",
        arguments: JSON.stringify({ fact: "Mario likes short answers" }),
      }])
      : textResponse("second", "Remembered."));
    const { store, assistant } = testRuntime(model);
    const events = await collect(assistant, { text: "Please remember that I like short answers", channel: "api" });
    expect(events.map((event) => event.type)).toEqual(["session", "tool_start", "tool_end", "text_delta", "done"]);
    const sessionEvent = events[0];
    if (sessionEvent?.type !== "session") throw new Error("missing session event");
    expect(store.getMessages(sessionEvent.session.id).map((message) => message.role)).toEqual(["user", "tool", "assistant"]);
    expect(store.searchMemories("personal", "short answers")[0]).toBe("Mario likes short answers");
    expect((model.calls[1]?.input.at(-1) as ResponseInputItem.FunctionCallOutput).type).toBe("function_call_output");
    expect(model.calls.every((call) => call.model === "gpt-5.6-luna" && call.reasoningEffort === "high")).toBe(true);
  });

  it("runs coding through Sol-high before Luna-high synthesis without exposing the worker", async () => {
    const model = routingModel();
    const { path, assistant } = testRuntime(model);
    const events = await collect(assistant, { text: "Fix the failing test", cwd: path, channel: "cli" });
    expect(model.calls.map((call) => [call.model, call.reasoningEffort])).toEqual([
      ["gpt-5.6-sol", "high"],
      ["gpt-5.6-luna", "high"],
    ]);
    expect(model.calls[0]?.tools.some((tool) => tool.name === "write_file")).toBe(true);
    expect(model.calls[1]?.tools.some((tool) => tool.name === "write_file")).toBe(false);
    expect(model.calls[1]?.instructions).toContain("<worker_result>");
    expect(events.map((event) => event.type)).toEqual(["session", "text_delta", "done"]);
  });

  it("never selects Astra automatically and permits it only on an explicit user request", async () => {
    const automatic = routingModel();
    const { path, store, assistant } = testRuntime(automatic);
    await collect(assistant, { text: "Investigate the root cause of this performance regression", channel: "api", fresh: true });
    expect(automatic.calls.map((call) => call.model)).toEqual(["gpt-5.6-luna", "gpt-5.6-luna"]);
    const explicit = routingModel();
    await collect(runtime(path, store, explicit), { text: "Use Astra high to investigate this code architecture", cwd: path, channel: "api", fresh: true });
    expect(explicit.calls.map((call) => call.model)).toEqual(["gpt-6-astra", "gpt-5.6-luna"]);
    expect(explicit.calls.every((call) => call.reasoningEffort === "high")).toBe(true);
    expect(explicit.calls[0]?.tools.some((tool) => tool.name === "read_file")).toBe(true);
    expect(explicit.calls[0]?.tools.some((tool) => tool.name === "write_file")).toBe(false);
  });

  it("reuses one personal session across CLI, Telegram, and macOS", async () => {
    const { store, assistant } = testRuntime(routingModel());
    const cli = await collect(assistant, { text: "hello", channel: "cli" });
    const cliSession = cli.find((event) => event.type === "session")?.session.id;
    const telegram = await collect(assistant, { text: "summarize this note", channel: "telegram" });
    const telegramSession = telegram.find((event) => event.type === "session")?.session.id;
    const macos = await collect(assistant, { text: "continue", channel: "macos", ...(cliSession ? { sessionId: cliSession } : {}) });
    const macosSession = macos.find((event) => event.type === "session")?.session.id;
    expect(telegramSession).toBe(cliSession);
    expect(macosSession).toBe(cliSession);
  });

  it("keeps the session resumable after an interrupted worker", async () => {
    const model = testModel((_request, call) => {
      if (call === 1) throw new DOMException("Interrupted", "AbortError");
      return textResponse(randomUUID(), call === 2 ? "Worker recovered." : "Recovered.");
    });
    const { path, assistant } = testRuntime(model);
    const interrupted = await collect(assistant, { text: "Fix the test", cwd: path, channel: "cli" });
    const session = interrupted.find((event) => event.type === "session")?.session;
    expect(interrupted.at(-1)).toMatchObject({ type: "error", message: "Interrupted. Your session is saved." });
    const resumed = await collect(assistant, { text: "continue fixing it", cwd: path, channel: "macos", sessionId: session?.id });
    expect(resumed.find((event) => event.type === "session")?.session.id).toBe(session?.id);
    expect(resumed.at(-1)?.type).toBe("done");
  });

  it("serializes simultaneous turns targeting the same session", async () => {
    let active = 0;
    let maxActive = 0;
    const model = testModel(async () => {
      maxActive = Math.max(maxActive, ++active);
      await new Promise((resolve) => setTimeout(resolve, 30));
      active -= 1;
      return textResponse(randomUUID(), "ok");
    });
    const { assistant } = testRuntime(model);
    await Promise.all([
      collect(assistant, { text: "hello", channel: "api" }),
      collect(assistant, { text: "hello again", channel: "api" }),
    ]);
    expect(maxActive).toBe(1);
  });

  it("transcribes runtime-owned audio before routing and persists the transcript", async () => {
    const transcriptions: string[] = [];
    const model = routingModel(async (attachment) => {
      transcriptions.push(attachment.path);
      return "Fix the TypeScript test";
    });
    const { path, store, assistant } = testRuntime(model);
    const audioPath = join(path, "voice.ogg");
    writeFileSync(audioPath, "audio");
    const events = await collect(assistant, {
      text: "",
      channel: "telegram",
      attachments: [{
        id: "voice-1",
        name: "voice.ogg",
        mimeType: "audio/ogg",
        size: 5,
        path: audioPath,
      }],
    });
    expect(events[0]).toEqual({ type: "status", message: "Listening…" });
    expect(events.find((event) => event.type === "session")?.session.kind).toBe("coding");
    expect(model.calls.map((call) => call.model)).toEqual(["gpt-5.6-sol", "gpt-5.6-luna"]);
    const session = events.find((event) => event.type === "session")?.session;
    expect(session && store.getMessages(session.id)[0]?.content).toBe("Fix the TypeScript test");
    expect(transcriptions).toEqual([audioPath]);
  });

  it("normalizes Responses image output into the shared artifact event", async () => {
    const model = testModel((request) => request.instructions.includes("internal Luna worker")
      ? textResponse("worker", "Generate the requested image.")
      : response("image-response", [{
        type: "image_generation_call", id: "image-1", status: "completed",
        result: Buffer.from("png-data").toString("base64"),
      }]));
    const { assistant } = testRuntime(model);
    const events = await collect(assistant, {
      text: "Create an image of a quiet blue horizon",
      channel: "api",
    });
    const event = events.find((candidate) => candidate.type === "artifact");
    expect(event).toMatchObject({ type: "artifact", artifact: { kind: "image", mimeType: "image/png" } });
    expect(event?.type === "artifact" && existsSync(event.artifact.path)).toBe(true);
    expect(events.at(-1)?.type).toBe("done");
  });
});
