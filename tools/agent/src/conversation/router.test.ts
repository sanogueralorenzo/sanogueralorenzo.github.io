import { describe, expect, it } from "vitest";
import { routeTurn } from "./router.js";

describe("routeTurn", () => {
  it.each([
    ["casual Telegram greeting", { text: "hello", channel: "telegram" } as const, undefined, { kind: "personal", worker: null }],
    ["project work", { text: "fix the failing test", cwd: "/tmp/project", channel: "cli" } as const, undefined, { kind: "coding", worker: "coding" }],
    ["personal work in a project", { text: "remind me about my family trip", cwd: "/tmp/project", channel: "cli" } as const, undefined, { kind: "personal" }],
    ["coding follow-up", { text: "continue", channel: "telegram" } as const, "coding" as const, { kind: "coding" }],
    ["bounded personal work", { text: "summarize this note", channel: "telegram" } as const, undefined, { kind: "personal", worker: "bounded" }],
  ])("routes %s", (_name, request, prior, expected) => {
    expect(routeTurn(request, prior)).toMatchObject(expected);
  });

  it("allows Astra only for an explicit positive request", () => {
    expect(routeTurn({ text: "Use Astra high to investigate this architecture" })).toMatchObject({ worker: "astra" });
    expect(routeTurn({ text: "Investigate this architecture without using Astra" })).not.toMatchObject({ worker: "astra" });
    expect(routeTurn({ text: "What is Astra?" })).not.toMatchObject({ worker: "astra" });
  });
});
