import assert from "node:assert/strict";
import { test, type TestContext } from "node:test";
import { mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { setTimeout as delay } from "node:timers/promises";
import { ComputerUseClient } from "./computer-use.ts";

type Event = { event?: string; pid?: number; method?: string; params?: { arguments?: { code?: string }; capabilities?: { elicitation?: unknown } } };
function fixture(t: TestContext, mode = "normal") {
  const dir = mkdtempSync(join(tmpdir(), "assistant-mcp-"));
  const log = join(dir, "messages.jsonl");
  const client = new ComputerUseClient(() => ({ command: process.execPath,
    args: [fileURLToPath(new URL("./fixtures/computer-use-server.mjs", import.meta.url))], env: { ASSISTANT_MCP_TEST_LOG: log, ASSISTANT_MCP_TEST_MODE: mode } }));
  const events = (): Event[] => { try { return readFileSync(log, "utf8").trim().split("\n").filter(Boolean).map(line => JSON.parse(line)); } catch { return []; } };
  t.after(async () => { await client.close(); rmSync(dir, { recursive: true, force: true }); });
  return { client, events };
}
async function until(condition: () => boolean) {
  const deadline = Date.now() + 5000;
  while (!condition()) { if (Date.now() > deadline) throw new Error("Timed out waiting for MCP process"); await delay(5); }
}
function alive(pid: number) { try { process.kill(pid, 0); return true; } catch { return false; } }
const text = (result: Awaited<ReturnType<ComputerUseClient["call"]>>) => result.content.filter(part => part.type === "text").map(part => part.text).join("\n");

test("one initialized MCP process preserves state and correlates out-of-order replies", async t => {
  const f = fixture(t);
  const [first, second] = await Promise.all([f.client.call("delayed", undefined, undefined), f.client.call("state", undefined, undefined)]);
  const a = JSON.parse(text(first)), b = JSON.parse(text(second));
  assert.equal(a.pid, b.pid); assert.equal(a.calls, 1); assert.equal(b.calls, 2);
  assert.equal(f.events().filter(event => event.method === "initialize").length, 1);
  assert.deepEqual(f.events().find(event => event.method === "initialize")?.params?.capabilities?.elicitation, { form: {} });
  await f.client.close(); assert.equal(alive(a.pid), false);
  await assert.rejects(f.client.call("state", undefined, undefined), /closed/);
});

test("the adapter preserves JS arguments and automatically accepts approval requests", async t => {
  const f = fixture(t);
  const result = await f.client.call("args", "Test title", 60000);
  assert.deepEqual(JSON.parse(text(result)), { code: "args", title: "Test title", timeout_ms: 60000 });
  assert.deepEqual(JSON.parse(text(await f.client.call("approve", undefined, undefined))), { action: "accept", content: {} });
});

test("Pi MCP converts text, images, embedded resources, and structured results", async t => {
  const f = fixture(t);
  const result = await f.client.call("media", undefined, undefined);
  assert.deepEqual(result.content, [
    { type: "text", text: "Image follows" }, { type: "image", mimeType: "image/png", data: "aW1hZ2U=" },
    { type: "text", text: "Embedded text" }, { type: "image", mimeType: "image/png", data: "ZW1iZWRkZWQ=" },
  ]);
  assert.deepEqual(JSON.parse(text(await f.client.call("structured", undefined, undefined))), { result: "structured" });
  assert.equal(text(await f.client.call("empty", undefined, undefined)), "Done.");
});

test("tool and protocol errors reach the agent without losing the live JS session", async t => {
  const f = fixture(t);
  await assert.rejects(f.client.call("error", undefined, undefined), /Script failed/);
  await assert.rejects(f.client.call("rpc-error", undefined, undefined), /RPC failed/);
  assert.equal(JSON.parse(text(await f.client.call("state", undefined, undefined))).calls, 3);
});

test("abort during initialization terminates the server and settles the call", async t => {
  const f = fixture(t, "stall-initialize");
  const controller = new AbortController();
  const call = f.client.call("state", undefined, undefined, controller.signal); void call.catch(() => {});
  await until(() => f.events().some(event => event.method === "initialize"));
  const pid = f.events()[0].pid!;
  controller.abort();
  await assert.rejects(call, /stopped/);
  assert.equal(alive(pid), false);
});

test("aborting a running call cancels it and waits for process shutdown", async t => {
  const f = fixture(t);
  const controller = new AbortController();
  const call = f.client.call("wait", undefined, undefined, controller.signal); void call.catch(() => {});
  await until(() => f.events().some(event => event.method === "tools/call"));
  const pid = f.events()[0].pid!;
  controller.abort();
  await assert.rejects(call, /stopped/);
  assert.equal(alive(pid), false);
  assert.ok(f.events().some(event => event.method === "notifications/cancelled"));
});

test("a pre-aborted call never starts a Computer Use process", async () => {
  let discovered = false;
  const client = new ComputerUseClient(() => { discovered = true; throw new Error("Must not discover"); });
  const controller = new AbortController(); controller.abort();
  await assert.rejects(client.call("state", undefined, undefined, controller.signal));
  assert.equal(discovered, false);
  await client.close();
});

test("initialization failures and server exits reject pending calls without leaking processes", async t => {
  const bad = fixture(t, "bad-initialize");
  await assert.rejects(bad.client.call("state", undefined, undefined), /Initialization failed/);
  assert.equal(alive(bad.events()[0].pid!), false);
  const f = fixture(t);
  const result = await f.client.call("state", undefined, undefined);
  const pid = JSON.parse(text(result)).pid;
  await assert.rejects(f.client.call("exit", undefined, undefined), /closed/i);
  assert.equal(alive(pid), false);
});

test("a transport deadline closes the server after the JS timeout grace period", async t => {
  const f = fixture(t);
  await assert.rejects(f.client.call("wait", undefined, 1), /timed out/i);
  assert.equal(alive(f.events()[0].pid!), false);
});

test("shutdown kills server descendants and escalates when a server ignores EOF and SIGTERM", async t => {
  const f = fixture(t);
  const pids = JSON.parse(text(await f.client.call("child", undefined, undefined)));
  await f.client.close();
  await until(() => !alive(pids.childPid));
  assert.equal(alive(pids.pid), false);
  const stubborn = fixture(t, "stubborn");
  const pid = JSON.parse(text(await stubborn.client.call("state", undefined, undefined))).pid;
  const close = stubborn.client.close();
  assert.equal(stubborn.client.close(), close);
  await close; assert.equal(alive(pid), false);
});
