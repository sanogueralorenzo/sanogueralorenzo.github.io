import assert from "node:assert/strict";
import { test } from "node:test";
import { hostedSearchLabel } from "./hosted-search.ts";

test("provider events identify hosted searches and page opens", () => {
  for (const data of [null, "invalid", {}, { type: "response.output_item.done", item: { type: "message" } },
    { type: "response.web_search_call.in_progress", item: { type: "web_search_call" } }]) assert.equal(hostedSearchLabel(data), undefined);
  const events = [
    { type: "response.output_item.added", item: { type: "web_search_call" } },
    { type: "response.output_item.done", item: { type: "web_search_call", action: { type: "search", queries: [" Pi "] } } },
    { type: "response.output_item.done", item: { type: "web_search_call", action: { type: "open_page", url: "https://www.pi.dev/docs" } } },
    { type: "response.output_item.done", item: { type: "web_search_call", action: { type: "open_page", url: "search-reference" } } },
  ];
  assert.deepEqual(events.map(hostedSearchLabel), ["Web search", "Web search: Pi", "Opening: pi.dev/docs", "Web search"]);
});
