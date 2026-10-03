import assert from "node:assert/strict";
import { test } from "node:test";
import type { ExtensionAPI, ProviderStreamEvent } from "@earendil-works/pi-coding-agent";
import { trackHostedSearch } from "./hosted-search.ts";

function tracker(labels: string[]) {
  let receive: (event: ProviderStreamEvent) => void;
  trackHostedSearch({ on(name: string, handler: typeof receive) {
    assert.equal(name, "provider_stream_event");
    receive = handler;
    return () => {};
  } } as ExtensionAPI, (label) => labels.push(label));
  return (data: unknown) => receive({ type: "provider_stream_event", provider: "openai-codex", api: "openai-codex-responses", model: "gpt-6-luna", data });
}

test("native provider events report hosted searches and page opens", () => {
  const labels: string[] = [];
  const receive = tracker(labels);
  for (const data of [null, "invalid", {}, { type: "response.output_item.done", item: { type: "message" } },
    { type: "response.web_search_call.in_progress", item: { type: "web_search_call" } }]) receive(data);
  assert.deepEqual(labels, []);
  receive({ type: "response.output_item.added", item: { type: "web_search_call" } });
  receive({ type: "response.output_item.done", item: { type: "web_search_call", action: { type: "search", queries: [" Pi 1.0 "] } } });
  receive({ type: "response.output_item.done", item: { type: "web_search_call", action: { type: "open_page", url: "https://www.pi.dev/docs" } } });
  receive({ type: "response.output_item.done", item: { type: "web_search_call", action: { type: "open_page", url: "search-reference" } } });
  assert.deepEqual(labels, ["Web search", "Web search: Pi 1.0", "Opening: pi.dev/docs", "Web search"]);
});

test("interleaved provider events stay with their own session", () => {
  const first: string[] = [], second: string[] = [];
  const receiveFirst = tracker(first), receiveSecond = tracker(second);
  receiveFirst({ type: "response.output_item.added", item: { type: "web_search_call" } });
  receiveSecond({ type: "response.output_item.done", item: { type: "web_search_call", action: { type: "search", query: "second" } } });
  receiveFirst({ type: "response.output_item.done", item: { type: "web_search_call", action: { type: "search", query: "first" } } });
  assert.deepEqual(first, ["Web search", "Web search: first"]);
  assert.deepEqual(second, ["Web search: second"]);
});
