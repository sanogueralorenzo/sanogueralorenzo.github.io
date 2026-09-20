import { randomUUID } from "node:crypto";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import type { Response, ResponseInputItem } from "openai/resources/responses/responses";
import { afterEach, describe, expect, it } from "vitest";
import { BackendRegistry } from "./backend.js";
import type { ModelClient, ModelRequest, ModelStreamEvent } from "./model.js";
import { ResponsesBackend } from "./responses-backend.js";
import { AgentRuntime } from "./runtime.js";
import { Store } from "./store.js";
import type { RuntimeConfig, RuntimeEvent } from "./types.js";

const paths: string[] = [];

afterEach(() => {
  for (const path of paths.splice(0)) rmSync(path, { recursive: true, force: true });
});

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

class MemoryModel implements ModelClient {
  calls: ModelRequest[] = [];

  async *stream(request: ModelRequest): AsyncGenerator<ModelStreamEvent, Response> {
    this.calls.push(request);
    if (this.calls.length === 1) {
      return response("first", [{
        type: "function_call",
        call_id: "call-1",
        name: "remember",
        arguments: JSON.stringify({ fact: "Mario likes short answers" }),
      }]);
    }
    yield { type: "text_delta", delta: "Remembered." };
    return textResponse("second", "Remembered.");
  }
}

class RoutingModel implements ModelClient {
  calls: ModelRequest[] = [];

  async *stream(request: ModelRequest): AsyncGenerator<ModelStreamEvent, Response> {
    this.calls.push(request);
    if (request.model !== "gpt-5.6-luna" || request.instructions.includes("internal Luna worker") || request.instructions.includes("internal Sol") || request.instructions.includes("internal Astra")) {
      return textResponse(`worker-${this.calls.length}`, "Worker result.");
    }
    yield { type: "text_delta", delta: "Combined." };
    return textResponse(`coordinator-${this.calls.length}`, "Combined.");
  }
}

class LockingModel implements ModelClient {
  active = 0;
  maxActive = 0;

  async *stream(): AsyncGenerator<ModelStreamEvent, Response> {
    this.active += 1;
    this.maxActive = Math.max(this.maxActive, this.active);
    await new Promise((resolve) => setTimeout(resolve, 30));
    this.active -= 1;
    yield { type: "text_delta", delta: "ok" };
    return textResponse(randomUUID(), "ok");
  }
}

class InterruptOnceModel implements ModelClient {
  calls = 0;

  async *stream(): AsyncGenerator<ModelStreamEvent, Response> {
    this.calls += 1;
    if (this.calls === 1) throw new DOMException("Interrupted", "AbortError");
    return textResponse(randomUUID(), this.calls === 2 ? "Worker recovered." : "Recovered.");
  }
}

function config(homeDir: string): RuntimeConfig {
  return {
    homeDir,
    host: "127.0.0.1",
    port: 0,
    models: { coordinator: "gpt-5.6-luna", bounded: "gpt-5.6-luna", coding: "gpt-5.6-sol", astra: "gpt-6-astra" },
    maxToolRounds: 4,
    maxHistoryMessages: 20,
    codexCommand: "codex",
  };
}

function runtime(homeDir: string, store: Store, model: ModelClient): AgentRuntime {
  const currentConfig = config(homeDir);
  const responses = new ResponsesBackend(currentConfig, store, model);
  store.setSetting("backend", "responses");
  return new AgentRuntime(currentConfig, store, new BackendRegistry(store, responses));
}

async function collect(assistant: AgentRuntime, request: Parameters<AgentRuntime["run"]>[0]): Promise<RuntimeEvent[]> {
  const events: RuntimeEvent[] = [];
  for await (const event of assistant.run(request)) events.push(event);
  return events;
}

describe("AgentRuntime", () => {
  it("keeps memory and final synthesis on the persistent Luna-high coordinator", async () => {
    const path = mkdtempSync(join(tmpdir(), "agent-runtime-"));
    paths.push(path);
    const store = new Store(path);
    const model = new MemoryModel();
    const events = await collect(runtime(path, store, model), { text: "Please remember that I like short answers", channel: "api" });

    expect(events.map((event) => event.type)).toEqual(["session", "tool_start", "tool_end", "text_delta", "done"]);
    const sessionEvent = events[0];
    if (sessionEvent?.type !== "session") throw new Error("missing session event");
    expect(sessionEvent.model).toBe("gpt-5.6-luna");
    expect(store.getMessages(sessionEvent.session.id).map((message) => message.role)).toEqual(["user", "tool", "assistant"]);
    expect(store.searchMemories("personal", "short answers")[0]?.content).toBe("Mario likes short answers");
    expect((model.calls[1]?.input.at(-1) as ResponseInputItem.FunctionCallOutput).type).toBe("function_call_output");
    expect(model.calls.every((call) => call.model === "gpt-5.6-luna" && call.reasoningEffort === "high")).toBe(true);
    store.close();
  });

  it("runs coding through Sol-high before Luna-high synthesis without exposing the worker", async () => {
    const path = mkdtempSync(join(tmpdir(), "agent-runtime-"));
    paths.push(path);
    const store = new Store(path);
    const model = new RoutingModel();
    const events = await collect(runtime(path, store, model), { text: "Fix the failing test", cwd: path, channel: "cli" });

    expect(model.calls.map((call) => [call.model, call.reasoningEffort])).toEqual([
      ["gpt-5.6-sol", "high"],
      ["gpt-5.6-luna", "high"],
    ]);
    expect(model.calls[0]?.tools.some((tool) => tool.name === "write_file")).toBe(true);
    expect(model.calls[1]?.tools.some((tool) => tool.name === "write_file")).toBe(false);
    expect(model.calls[1]?.instructions).toContain("<worker_result>");
    expect(events.map((event) => event.type)).toEqual(["session", "text_delta", "done"]);
    store.close();
  });

  it("never selects Astra automatically and permits it only on an explicit user request", async () => {
    const path = mkdtempSync(join(tmpdir(), "agent-runtime-"));
    paths.push(path);
    const store = new Store(path);
    const automatic = new RoutingModel();
    const assistant = runtime(path, store, automatic);
    await collect(assistant, { text: "Investigate the root cause of this performance regression", channel: "api", fresh: true });
    expect(automatic.calls.map((call) => call.model)).toEqual(["gpt-5.6-luna", "gpt-5.6-luna"]);

    const explicit = new RoutingModel();
    await collect(runtime(path, store, explicit), { text: "Use Astra high to investigate this code architecture", cwd: path, channel: "api", fresh: true });
    expect(explicit.calls.map((call) => call.model)).toEqual(["gpt-6-astra", "gpt-5.6-luna"]);
    expect(explicit.calls.every((call) => call.reasoningEffort === "high")).toBe(true);
    expect(explicit.calls[0]?.tools.some((tool) => tool.name === "read_file")).toBe(true);
    expect(explicit.calls[0]?.tools.some((tool) => tool.name === "write_file")).toBe(false);
    store.close();
  });

  it("reuses one personal session across CLI, Telegram, and macOS", async () => {
    const path = mkdtempSync(join(tmpdir(), "agent-runtime-"));
    paths.push(path);
    const store = new Store(path);
    const assistant = runtime(path, store, new RoutingModel());
    const cli = await collect(assistant, { text: "hello", channel: "cli" });
    const cliSession = cli.find((event) => event.type === "session")?.session.id;
    const telegram = await collect(assistant, { text: "summarize this note", channel: "telegram", senderId: "42" });
    const telegramSession = telegram.find((event) => event.type === "session")?.session.id;
    const macos = await collect(assistant, { text: "continue", channel: "macos", ...(cliSession ? { sessionId: cliSession } : {}) });
    const macosSession = macos.find((event) => event.type === "session")?.session.id;

    expect(telegramSession).toBe(cliSession);
    expect(macosSession).toBe(cliSession);
    expect(store.gatewaySession("telegram", "42")?.id).toBe(cliSession);
    store.close();
  });

  it("keeps the session resumable after an interrupted worker", async () => {
    const path = mkdtempSync(join(tmpdir(), "agent-runtime-"));
    paths.push(path);
    const store = new Store(path);
    const assistant = runtime(path, store, new InterruptOnceModel());
    const interrupted = await collect(assistant, { text: "Fix the test", cwd: path, channel: "cli" });
    const session = interrupted.find((event) => event.type === "session")?.session;
    expect(interrupted.at(-1)).toMatchObject({ type: "error", message: "Interrupted. Your session is saved." });

    const resumed = await collect(assistant, { text: "continue fixing it", cwd: path, channel: "macos", sessionId: session?.id });
    expect(resumed.find((event) => event.type === "session")?.session.id).toBe(session?.id);
    expect(resumed.at(-1)?.type).toBe("done");
    store.close();
  });

  it("serializes simultaneous turns targeting the same session", async () => {
    const path = mkdtempSync(join(tmpdir(), "agent-runtime-"));
    paths.push(path);
    const store = new Store(path);
    const model = new LockingModel();
    const assistant = runtime(path, store, model);
    await Promise.all([
      collect(assistant, { text: "hello", channel: "api" }),
      collect(assistant, { text: "hello again", channel: "api" }),
    ]);
    expect(model.maxActive).toBe(1);
    store.close();
  });
});
