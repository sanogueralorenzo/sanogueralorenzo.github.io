import { existsSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";
import { BackendRegistry, type BackendTurn } from "../conversation/backend.js";
import { AgentRuntime } from "../conversation/runtime.js";
import { Store } from "../conversation/store.js";
import type { RuntimeConfig } from "../conversation/types.js";
import { cleanup, temporary } from "../test-support.js";
import { CodexAppServer } from "./app-server.js";
import { CodexBackend } from "./backend.js";

const fixture = join(dirname(fileURLToPath(import.meta.url)), "test-fixtures", "fake-app-server.mjs");

function client(scenario: string, extra: NodeJS.ProcessEnv = {}): CodexAppServer {
  const appServer = new CodexAppServer({
    command: process.execPath,
    args: [fixture],
    env: { ...process.env, AGENT_FAKE_SCENARIO: scenario, ...extra },
  });
  cleanup(() => appServer.stop());
  return appServer;
}

function trackedStore(homeDir: string): Store {
  const value = new Store(homeDir);
  cleanup(() => value.close());
  return value;
}

const requests = (log: string) => readFileSync(log, "utf8").trim().split("\n")
  .map((line) => JSON.parse(line) as { method: string; params: Record<string, unknown> });

const config = (homeDir: string): RuntimeConfig => ({ homeDir, port: 0, codexCommand: "codex" });

function turn(store: Store, homeDir: string, worker: BackendTurn["route"]["worker"] = "coding"): BackendTurn {
  const session = store.resolveSession({ scopeKey: "project:test", kind: "coding", cwd: homeDir, title: "test" });
  return {
    request: { text: "Fix the test", cwd: homeDir, channel: "api" },
    session,
    route: { kind: "coding", worker },
    instructions: "Act as Agent. Use the supplied memory.",
    workerInstructions: "Act as Agent's internal coding worker.",
    memoryScope: `project:${homeDir}`,
  };
}

async function collect(backend: CodexBackend, input: BackendTurn) {
  const events = [];
  for await (const event of backend.run(input)) events.push(event);
  return events;
}

function backendFixture(scenario = "normal", extra: NodeJS.ProcessEnv = {}, worker: BackendTurn["route"]["worker"] = null) {
  const homeDir = temporary("agent-codex-");
  const log = join(homeDir, "rpc.log");
  const store = trackedStore(homeDir);
  const backend = new CodexBackend(config(homeDir), store, client(scenario, { AGENT_FAKE_LOG: log, ...extra }));
  return { homeDir, log, store, backend, input: turn(store, homeDir, worker) };
}

describe("Codex turn transport", () => {
  it("normalizes streamed agent and tool events", async () => {
    const { store, backend, input } = backendFixture();
    const events = await collect(backend, input);
    expect(events.map((event) => event.type)).toEqual(["tool_start", "tool_end", "text_delta", "done"]);
    expect(events.find((event) => event.type === "text_delta")).toMatchObject({ delta: "Hello from Codex." });
    expect(store.backendSession(input.session.id, "codex")).toBe("thread-1");
  });

  it("streams Opus through private Codex realtime for runtime-owned transcription", async () => {
    const homeDir = temporary("agent-codex-voice-");
    const log = join(homeDir, "rpc.log");
    const audioPath = join(homeDir, "voice.ogg");
    writeFileSync(audioPath, Buffer.from("T2dnUwACAAAAAAAAAAA4TQibAAAAABbLz/IBE09wdXNIZWFkAQE4AYC7AAAAAABPZ2dTAAAAAAAAAAAAADhNCJsBAAAACYU5GQE8T3B1c1RhZ3MMAAAATGF2ZjYzLjEuMTAyAQAAABwAAABlbmNvZGVyPUxhdmM2My4xLjEwMiBsaWJvcHVzT2dnUwAEuAgAAAAAAAA4TQibAgAAAASvZ7YDDRYOCINtgtAc/epJ/gE/wAinGl2KmC5fbwXLShrtt/PI1gXBXsAIBm0zkArsfUCzkSIpxA==", "base64"));
    const store = trackedStore(homeDir);
    const accepted: string[] = [];
    const sent: number[] = [];
    const backend = new CodexBackend(config(homeDir), store, client("normal", { AGENT_FAKE_LOG: log }), () => ({
      offer: async () => "fake-offer",
      accept: async (sdp) => { accepted.push(sdp); },
      sendAudio: async (audio) => { sent.push(audio.frames.length); },
      close: async () => undefined,
    }));
    await expect(backend.transcribeAudio({
      id: "voice-1", name: "voice.ogg", mimeType: "audio/ogg", size: 214, path: audioPath,
    })).resolves.toBe("Hello from Codex.");
    const rpc = requests(log);
    expect(rpc.some((request) => request.method === "turn/start")).toBe(false);
    expect(rpc.find((request) => request.method === "thread/realtime/start")?.params).toMatchObject({
      outputModality: "audio",
      includeStartupContext: false,
      clientManagedHandoffs: true,
      version: "v3",
      transport: { type: "webrtc", sdp: "fake-offer" },
    });
    expect(accepted).toEqual(["fake-answer"]);
    expect(sent[0]).toBeGreaterThan(0);
    expect(rpc.some((request) => request.method === "thread/realtime/appendAudio")).toBe(false);
    expect(rpc.at(-1)?.method).toBe("thread/realtime/stop");
    expect(readFileSync(log, "utf8")).not.toContain("OPENAI_API_KEY");
  });

  it("copies generated images into one backend-neutral artifact event", async () => {
    const homeDir = temporary("agent-codex-artifact-");
    const generated = join(homeDir, "generated.png");
    writeFileSync(generated, "png-data");
    const store = trackedStore(homeDir);
    const backend = new CodexBackend(config(homeDir), store, client("image", { AGENT_FAKE_ARTIFACT: generated }));
    const events = await collect(backend, turn(store, homeDir, null));
    const event = events.find((candidate) => candidate.type === "artifact");
    expect(event).toMatchObject({ type: "artifact", artifact: { kind: "image", name: "generated.png", mimeType: "image/png" } });
    expect(event?.type === "artifact" && event.artifact.path).not.toBe(generated);
    expect(event?.type === "artifact" && existsSync(event.artifact.path)).toBe(true);
  });

  it.each([
    ["coding", ["gpt-5.6-sol", "gpt-5.6-luna"], ["workspace-write", "read-only"]],
    ["astra", ["gpt-6-astra", "gpt-5.6-luna"], ["read-only", "read-only"]],
  ] as const)("translates the %s worker into app-server settings", async (worker, models, sandboxes) => {
    const { backend, input, log } = backendFixture("normal", {}, worker);
    await collect(backend, input);
    const rpc = requests(log);
    const threads = rpc.filter((request) => request.method === "thread/start");
    expect(threads.map((request) => request.params.model)).toEqual(models);
    expect(threads.map((request) => request.params.sandbox)).toEqual(sandboxes);
    expect(threads.map((request) => request.params.ephemeral)).toEqual([true, false]);
    expect(rpc.filter((request) => request.method === "turn/start").map((request) => request.params.effort)).toEqual(["high", "high"]);
  });

  it("preserves the runtime session and event contract", async () => {
    const homeDir = temporary("agent-codex-runtime-");
    const store = trackedStore(homeDir);
    store.setSetting("backend", "codex");
    const codex = new CodexBackend(config(homeDir), store, client("normal"));
    const runtime = new AgentRuntime(store, new BackendRegistry(store, codex, codex));
    const events = [];
    for await (const event of runtime.run({ text: "Fix the test", cwd: homeDir, channel: "api" })) events.push(event);
    expect(events.map((event) => event.type)).toEqual(["session", "tool_start", "tool_end", "text_delta", "done"]);
    const session = events[0]?.type === "session" ? events[0].session : null;
    expect(session && store.getMessages(session.id).map((message) => message.role)).toEqual(["user", "tool", "assistant"]);
  });

  it("interrupts an active turn through turn/interrupt", async () => {
    const { backend, input, log } = backendFixture("cancel");
    const controller = new AbortController();
    const running = collect(backend, { ...input, signal: controller.signal });
    setTimeout(() => controller.abort(), 50);
    await expect(running).rejects.toMatchObject({ name: "AbortError" });
    await new Promise((resolve) => setTimeout(resolve, 30));
    expect(readFileSync(log, "utf8")).toContain("turn/interrupt");
  });

  it("restarts app-server and resumes the opaque Codex thread", async () => {
    const homeDir = temporary("agent-codex-reconnect-marker-");
    const marker = join(homeDir, "restart.marker");
    const fixture = backendFixture("reconnect", { AGENT_FAKE_MARKER: marker });
    const events = await collect(fixture.backend, fixture.input);
    expect(events).toContainEqual({ type: "text_delta", delta: "Hello from Codex." });
    expect(requests(fixture.log).filter((request) => request.method.startsWith("thread/")).map((request) => request.method))
      .toEqual(["thread/start", "thread/resume"]);
  });

  it("does not replace a missing Codex thread", async () => {
    const { backend, input, store, log } = backendFixture("missing-thread", {}, null);
    store.bindBackendSession(input.session.id, "codex", "missing-thread-id");
    await expect(collect(backend, input)).rejects.toThrow("thread not found");
    expect(readFileSync(log, "utf8")).toContain("thread/resume");
    expect(readFileSync(log, "utf8")).not.toContain("thread/start");
    expect(store.backendSession(input.session.id, "codex")).toBe("missing-thread-id");
  });

  it.each([
    ["expired", /session has expired/],
    ["exhausted", /allowance is currently exhausted/],
  ])("classifies %s account failures", async (scenario, message) => {
    const { backend, input } = backendFixture(scenario);
    await expect(collect(backend, input)).rejects.toThrow(message);
  });
});
