import { describe, expect, it } from "vitest";
import { routeTurn } from "./router.js";

describe("routeTurn", () => {
  it("routes a casual Telegram message as fast personal work", () => {
    expect(routeTurn({ text: "hello", channel: "telegram" })).toMatchObject({
      kind: "personal",
      tier: "fast",
      allowTools: false,
    });
  });

  it("routes project work as coding", () => {
    expect(routeTurn({ text: "fix the failing test", cwd: "/tmp/project", channel: "cli" })).toMatchObject({
      kind: "coding",
      allowTools: true,
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

  it("reserves the deep tier for complex work", () => {
    expect(routeTurn({ text: "investigate the root cause of this performance regression" })).toMatchObject({
      tier: "deep",
      allowDelegation: true,
    });
  });
});
