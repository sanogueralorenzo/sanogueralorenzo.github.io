import { describe, expect, it } from "vitest";
import { routeTurn } from "./router.js";

describe("routeTurn", () => {
  it("keeps a casual Telegram greeting on the coordinator", () => {
    expect(routeTurn({ text: "hello", channel: "telegram" })).toMatchObject({
      kind: "personal",
      worker: null,
    });
  });

  it("routes project work as coding", () => {
    expect(routeTurn({ text: "fix the failing test", cwd: "/tmp/project", channel: "cli" })).toMatchObject({
      kind: "coding",
      worker: "coding",
    });
  });

  it("lets explicit personal work override the current project", () => {
    expect(routeTurn({ text: "remind me about my family trip", cwd: "/tmp/project", channel: "cli" })).toMatchObject({
      kind: "personal",
    });
  });

  it("keeps ambiguous follow-ups in the active coding session", () => {
    expect(routeTurn({ text: "continue", channel: "telegram" }, "coding")).toMatchObject({ kind: "coding" });
  });

  it("uses Luna for bounded personal work", () => {
    expect(routeTurn({ text: "summarize this note", channel: "telegram" })).toMatchObject({
      kind: "personal",
      worker: "bounded",
    });
  });

  it("allows Astra only for an explicit positive request", () => {
    expect(routeTurn({ text: "Use Astra high to investigate this architecture" })).toMatchObject({ worker: "astra" });
    expect(routeTurn({ text: "Investigate this architecture without using Astra" })).not.toMatchObject({ worker: "astra" });
    expect(routeTurn({ text: "What is Astra?" })).not.toMatchObject({ worker: "astra" });
  });
});
