import { describe, expect, it, vi } from "vitest";
import { CliOutput } from "./output.js";
import type { RunEnvelope, Session } from "../conversation/types.js";

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

  it("waits for the destination answer instead of ending at navigation", async () => {
    const write = vi.spyOn(process.stdout, "write").mockImplementation(() => true);
    try {
      const target: Session = { id: "target", cwd: "/project", title: "Project", updatedAt: new Date().toISOString() };
      const changeSession = vi.fn();
      const output = new CliOutput("source", vi.fn(), changeSession, () => false);
      output.submitted("r1");
      let finished = false;
      const completion = output.waitFor("r1").then(() => { finished = true; });
      const render = (event: RunEnvelope["event"], sessionId = "target") => output.render({ sessionId, runId: "r1", event });

      render({ type: "navigate", session: target, url: "agent://sessions/target", continues: true }, "source");
      await Promise.resolve();
      expect(finished).toBe(false);
      expect(output.activeRunId).toBe("r1");
      expect(changeSession).toHaveBeenCalledWith("target");

      render({ type: "text_delta", delta: "Finished." });
      render({ type: "done", sessionId: "target" });
      await completion;
      expect(write.mock.calls.map(([text]) => String(text)).join("")).toContain("Finished.");
    } finally {
      write.mockRestore();
    }
  });

  it("uses the same opening boundary when recovering a missed switch", () => {
    const target: Session = { id: "target", cwd: null, title: "Saved work", updatedAt: "now" };
    const status = vi.fn();
    const changeSession = vi.fn();
    const output = new CliOutput("source", status, changeSession, () => false);
    output.render({ sessionId: "source", runId: "", event: { type: "snapshot", snapshot: {
      sessions: [], homeEntries: [], transcript: null, lastRuns: [], activeRuns: [{
        run: { id: "r1", sessionId: "source", origin: "cli" },
        turn: { type: "turn", text: "Resume saved work", channel: "cli", hasAttachments: false },
        session: target, output: "", artifacts: [],
        navigation: { type: "navigate", session: target, url: "agent://sessions/target", continues: true },
      }],
    } } });
    expect(status).toHaveBeenCalledWith("Opened “Saved work”.");
    expect(changeSession).toHaveBeenCalledWith("target");
  });
});
