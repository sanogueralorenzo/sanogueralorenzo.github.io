import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import type { Response, ResponseInputItem } from "openai/resources/responses/responses";
import { afterEach, describe, expect, it } from "vitest";
import type { ModelClient, ModelRequest, ModelStreamEvent } from "./model.js";
import { BackendRegistry } from "./backend.js";
import { ResponsesBackend } from "./responses-backend.js";
import { A1RRuntime } from "./runtime.js";
import { Store } from "./store.js";
import type { RuntimeConfig } from "./types.js";

const paths: string[] = [];

afterEach(() => {
  for (const path of paths.splice(0)) rmSync(path, { recursive: true, force: true });
});

function response(id: string, output: Response["output"], outputText = ""): Response {
  return { id, output, output_text: outputText } as Response;
}

class FakeModel implements ModelClient {
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
    return response("second", [{
      type: "message",
      id: "message-1",
      role: "assistant",
      status: "completed",
      content: [{ type: "output_text", text: "Remembered.", annotations: [], logprobs: [] }],
    }], "Remembered.");
  }

  async delegate(): Promise<string> {
    return "worker result";
  }
}

class ParallelDelegateModel implements ModelClient {
  calls = 0;
  activeDelegates = 0;
  maxActiveDelegates = 0;

  async *stream(_request: ModelRequest): AsyncGenerator<ModelStreamEvent, Response> {
    this.calls += 1;
    if (this.calls === 1) {
      return response("delegating", ["one", "two"].map((task, index) => ({
        type: "function_call",
        call_id: `delegate-${index}`,
        name: "delegate_task",
        arguments: JSON.stringify({ task }),
      })));
    }
    yield { type: "text_delta", delta: "Combined." };
    return response("combined", [], "Combined.");
  }

  async delegate(task: string): Promise<string> {
    this.activeDelegates += 1;
    this.maxActiveDelegates = Math.max(this.maxActiveDelegates, this.activeDelegates);
    await new Promise((resolve) => setTimeout(resolve, 40));
    this.activeDelegates -= 1;
    return `${task} done`;
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
    return response(randomUUID(), [], "ok");
  }

  async delegate(): Promise<string> { return ""; }
}

function config(homeDir: string): RuntimeConfig {
  return {
    homeDir,
    host: "127.0.0.1",
    port: 0,
    models: { fast: "fast-model", standard: "standard-model", deep: "deep-model" },
    maxToolRounds: 4,
    maxHistoryMessages: 20,
    codexCommand: "codex",
  };
}

function runtime(homeDir: string, store: Store, model: ModelClient): A1RRuntime {
  const currentConfig = config(homeDir);
  const responses = new ResponsesBackend(currentConfig, store, model);
  store.setSetting("backend", "responses");
  return new A1RRuntime(currentConfig, store, new BackendRegistry(store, responses));
}

describe("A1RRuntime", () => {
  it("owns the tool loop, memory, transcript, and streamed events", async () => {
    const path = mkdtempSync(join(tmpdir(), "a1r-runtime-"));
    paths.push(path);
    const store = new Store(path);
    const model = new FakeModel();
    const assistant = runtime(path, store, model);
    const events = [];

    for await (const event of assistant.run({ text: "Please remember that I like short answers", channel: "api" })) {
      events.push(event);
    }

    expect(events.map((event) => event.type)).toEqual([
      "session", "tool_start", "tool_end", "text_delta", "done",
    ]);
    const sessionEvent = events[0];
    expect(sessionEvent?.type).toBe("session");
    if (sessionEvent?.type !== "session") throw new Error("missing session event");
    expect(store.getMessages(sessionEvent.session.id).map((message) => message.role)).toEqual(["user", "tool", "assistant"]);
    expect(store.searchMemories("personal", "short answers")[0]?.content).toBe("Mario likes short answers");
    expect((model.calls[1]?.input.at(-1) as ResponseInputItem.FunctionCallOutput).type).toBe("function_call_output");
    store.close();
  });

  it("runs independent internal delegates concurrently", async () => {
    const path = mkdtempSync(join(tmpdir(), "a1r-runtime-"));
    paths.push(path);
    const store = new Store(path);
    const model = new ParallelDelegateModel();
    const assistant = runtime(path, store, model);

    for await (const _event of assistant.run({ text: "investigate the root cause and compare both approaches", channel: "api" })) { /* consume */ }

    expect(model.maxActiveDelegates).toBe(2);
    store.close();
  });

  it("serializes simultaneous turns targeting the same session", async () => {
    const path = mkdtempSync(join(tmpdir(), "a1r-runtime-"));
    paths.push(path);
    const store = new Store(path);
    const model = new LockingModel();
    const assistant = runtime(path, store, model);
    const collect = async (text: string) => {
      for await (const _event of assistant.run({ text, channel: "api" })) { /* consume */ }
    };

    await Promise.all([collect("hello one"), collect("hello two")]);

    expect(model.maxActive).toBe(1);
    store.close();
  });
});
import { randomUUID } from "node:crypto";
