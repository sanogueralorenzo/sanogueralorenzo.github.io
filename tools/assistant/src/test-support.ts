import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import type { TestContext } from "node:test";
import type { JsonValue } from "@earendil-works/chord";
import { BACKGROUND_CONTEXT } from "@earendil-works/chord/context";
import { createModels } from "@earendil-works/pi-ai";
import { fauxProvider, fauxAssistantMessage, fauxToolCall, type FauxResponseStep, type RegisterFauxProviderOptions } from "@earendil-works/pi-ai/providers/faux";
import { defineTool, type Extension, type ToolRegistration } from "@earendil-works/pi-durable";
import { Type } from "typebox";
import { Assistant } from "./assistant.ts";
import { roleExtension } from "./pi.ts";

export async function fixture(t: TestContext, responses: FauxResponseStep[] = [fauxAssistantMessage("First proposal.\nIts details.")], tools: ToolRegistration[] = [], fauxOptions: RegisterFauxProviderOptions = {}, extensions: Extension[] = []) {
  const dir = mkdtempSync(join(tmpdir(), "assistant-durable-test-"));
  const faux = fauxProvider({ tokensPerSecond: 100000, ...fauxOptions });
  const models = createModels(); models.setProvider(faux.provider);
  const options = { models, model: { provider: "faux", modelId: "faux-1" }, extensions: [...(tools.length ? [roleExtension("session", tools)] : []), ...extensions] };
  let app = await Assistant.open(dir, dir, options);
  faux.setResponses([fauxAssistantMessage(fauxToolCall("route_home", { mode: "start", title: "Test", cwd: dir }), { stopReason: "toolUse" }), ...responses]);
  t.after(async () => { await app.shutdown(); rmSync(dir, { recursive: true, force: true }); });
  const source = await app.submitHome("Original request");
  await waitFor(app, () => !!app.snapshot().sessions.length);
  const sessionId = app.snapshot().sessions[0].id;
  return { app, dir, faux, models, options, sourceId: source.id, sessionId,
    idle: () => app.pi.harness.waitForIdle(BACKGROUND_CONTEXT),
    reopen: async () => { await app.shutdown(); app = await Assistant.open(dir, dir, options); return app; } };
}
export function waitFor(app: Assistant, condition: () => boolean): Promise<void> {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => { unsubscribe(); reject(new Error(`Timed out: ${JSON.stringify(app.snapshot())}`)); }, 10000);
    const check = () => { if (condition()) { clearTimeout(timer); unsubscribe(); resolve(); } };
    const unsubscribe = app.subscribe(check);
    check();
  });
}
export function gate(replay: "safe" | "unsafe" = "unsafe") {
  let release!: () => void;
  let start!: () => void;
  const started = new Promise<void>((resolve) => { start = resolve; });
  const pending = new Promise<void>((resolve) => { release = resolve; });
  let calls = 0;
  const tool = defineTool({ name: "pause", description: "Wait for the test to release execution", parameters: Type.Object({}), replay,
    execute: async (_args, _api, context) => {
      calls++; start();
      await new Promise<void>((resolve, reject) => {
        const abort = () => { cleanup(); reject(context.abortSignal!.reason); };
        const cleanup = () => context.abortSignal?.removeEventListener("abort", abort);
        context.abortSignal?.addEventListener("abort", abort, { once: true });
        void pending.then(() => { cleanup(); resolve(); });
        if (context.abortSignal?.aborted) abort();
      });
      return { content: [{ type: "text", text: "Released" }] };
    } });
  return { tool, started, release, calls: () => calls };
}
export const toolAnswer = (name: string, args: Record<string, JsonValue> = {}) => fauxAssistantMessage(fauxToolCall(name, args), { stopReason: "toolUse" });
export const answered = (app: Assistant, sessionId: string) => app.transcript(sessionId).messages.filter((message) => message.completed);
export function assertQueued(app: Assistant, sessionId: string, count: number) {
  assert.equal(app.snapshot().turns.filter((turn) => turn.sessionId === sessionId && turn.status === "queued").length, count);
}
