import { describe, expect, it } from "vitest";
import { CliOutput } from "./output.js";

describe("CLI output", () => {
  it("finishes a submitted run whose completion arrived first without retaining old completions forever", async () => {
    const output = new CliOutput("session", () => undefined, () => undefined, () => false);
    for (let index = 0; index < 40; index += 1) {
      const runId = `run-${index}`;
      output.render({ sessionId: "session", runId, event: { type: "turn", text: "hello", channel: "cli", hasAttachments: false } });
      output.render({ sessionId: "session", runId, event: { type: "done", sessionId: "session" } });
    }

    output.submitted("run-39");
    await expect(output.waitFor("run-39")).resolves.toBeUndefined();
    let oldRunResolved = false;
    void output.waitFor("run-0").then(() => { oldRunResolved = true; });
    await Promise.resolve();
    expect(oldRunResolved).toBe(false);
    output.resolveWaiters();
  });
});
