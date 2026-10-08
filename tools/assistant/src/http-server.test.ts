import assert from "node:assert/strict";
import { test } from "node:test";
import { once } from "node:events";
import { fauxAssistantMessage, fauxToolCall } from "@earendil-works/pi-ai/providers/faux";
import { createAssistantServer } from "./http-server.ts";
import { fixture, gate, toolAnswer, waitFor } from "./test-support.ts";

async function host(app: Parameters<typeof createAssistantServer>[0]) {
  const http = createAssistantServer(app);
  http.server.listen(0, "127.0.0.1"); await once(http.server, "listening");
  const address = http.server.address();
  assert.ok(address && typeof address === "object");
  return { ...http, url: `http://127.0.0.1:${address.port}` };
}

test("HTTP returns concrete async receipts and SSE reconnects with the saved conversation", async (t) => {
  const f = await fixture(t); await f.idle();
  const http = await host(f.app); t.after(http.close);
  assert.match(await (await fetch(http.url)).text(), /Assistant/);
  const post = async (path: string, body: unknown) => fetch(`${http.url}${path}`, { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify(body) });
  const reply = f.app.transcript(f.sessionId).messages.at(-1)!;
  f.faux.appendResponses([fauxAssistantMessage("Second answer.")]);
  const response = await post("/api/turns", { sessionId: f.sessionId, text: "Follow up", replyToId: reply.id });
  assert.equal(response.status, 202);
  assert.ok((await response.json()).turn.id);
  await f.idle();
  const controller = new AbortController(); t.after(() => controller.abort());
  const stream = await fetch(`${http.url}/api/events`, { signal: controller.signal });
  assert.match(stream.headers.get("content-type") || "", /text\/event-stream/);
  const reader = stream.body!.getReader(); let text = "";
  while (!text.includes('"type":"conversation"')) text += new TextDecoder().decode((await reader.read()).value);
  const events = text.trim().split("\n\n").map((frame) => JSON.parse(frame.slice(6)));
  const conversation = events.find((event) => event.type === "conversation");
  assert.equal(conversation.sessionId, f.sessionId);
  assert.equal(conversation.messages.at(-1).text, "Second answer.");
  assert.equal(conversation.streaming, "");
  controller.abort();
  const invalid = await post("/api/turns", { sessionId: f.sessionId, text: "x", replyToId: "missing" });
  assert.equal(invalid.status, 400);
  assert.match((await invalid.json()).error, /not in this conversation/);
});

test("HTTP queue withdrawal and Stop use the Durable inbox and return saved results", async (t) => {
  const pause = gate();
  const f = await fixture(t, [toolAnswer("pause")], [pause.tool]); await pause.started;
  const http = await host(f.app); t.after(http.close);
  const post = async (path: string, body: unknown) => {
    const response = await fetch(`${http.url}${path}`, { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify(body) });
    assert.ok(response.ok); return response.json();
  };
  await post("/api/turns", { sessionId: f.sessionId, text: "Queued request" });
  await waitFor(f.app, () => f.app.state.home.messages.at(-1)?.submissionId !== undefined);
  const turn = f.app.snapshot().turns.find((turn) => turn.status === "queued")!;
  const removed = await post("/api/dequeue", { sessionId: f.sessionId, turnId: turn.id });
  assert.equal(removed.message.text, "Queued request");
  assert.equal(removed.removedMessageId, turn.sourceId);
  assert.deepEqual(await post("/api/stop", { sessionId: f.sessionId }), { stopped: true });
  const result = await (await fetch(`${http.url}/api/sessions/${f.sessionId}`)).json();
  assert.equal(result.session.status, "interrupted");
  assert.equal(result.queue.length, 0);
});


test("SSE discovers a new conversation and reconnects to its in-flight text", async (t) => {
  const f = await fixture(t, [fauxAssistantMessage("First reply.")], [], { tokensPerSecond: 1000, tokenSize: { min: 1, max: 1 } });
  await f.idle();
  const http = await host(f.app); t.after(http.close);
  const connect = async () => {
    const controller = new AbortController(); t.after(() => controller.abort());
    const response = await fetch(`${http.url}/api/events`, { signal: controller.signal });
    const reader = response.body!.getReader();
    const events: Array<{ type: string; sessionId?: string; streaming?: string }> = [];
    let pending = "";
    const done = (async () => {
      try {
        for (;;) {
          const { value, done } = await reader.read(); if (done) return;
          pending += new TextDecoder().decode(value);
          let end: number;
          while ((end = pending.indexOf("\n\n")) !== -1) {
            events.push(JSON.parse(pending.slice(6, end))); pending = pending.slice(end + 2);
          }
        }
      } catch (error) { if (!controller.signal.aborted) throw error; }
    })();
    return { controller, events, done };
  };
  const first = await connect();
  f.faux.appendResponses([fauxAssistantMessage(fauxToolCall("route_home", { mode: "start", title: "New conversation", cwd: f.dir }), { stopReason: "toolUse" }), fauxAssistantMessage("Native streamed text. ".repeat(100))]);
  await f.app.submitHome("Start another conversation");
  await waitFor(f.app, () => f.app.snapshot().sessions.length === 2);
  const id = f.app.snapshot().sessions[1].id;
  await waitFor(f.app, () => first.events.some((event) => event.sessionId === id && event.streaming));
  first.controller.abort(); await first.done;
  const second = await connect();
  await waitFor(f.app, () => second.events.some((event) => event.sessionId === id && event.streaming));
  assert.match(second.events.find((event) => event.sessionId === id && event.streaming)!.streaming!, /^Native streamed/);
  await f.app.stop(id);
  second.controller.abort(); await second.done;
});
