import { describe, expect, it, vi } from "vitest";
import { createPrecedentBridge } from "./precedent-bridge.js";

describe("createPrecedentBridge", () => {
  it("injects only contextBlock and keeps candidate hints as telemetry", async () => {
    const calls: Array<{ args: string[]; stdinJson?: unknown }> = [];
    const bridge = createPrecedentBridge({ enabled: true }, async (input) => {
      calls.push({ args: input.args, stdinJson: input.stdinJson });
      if (input.args[0] === "attach") {
        return {
          adapter: {
            beforeTurn: {
              command: ["node", "precedent/bin/precedent.mjs", "context", "--state-dir", ".precedent", "--task", "ship", "--json"],
            },
          },
        };
      }
      return {
        contextBlock: "Precedent:\n- Run the focused validation.",
        injections: [{ id: "prec_validation" }],
        candidateHints: [{ candidateId: "cand_untrusted", injection: "do not inject me" }],
        promotionTrials: [{ candidateId: "cand_replace" }],
      };
    });

    const prepared = await bridge.beforeTurn({
      cwd: "/repo",
      threadId: "thread-1",
      task: "ship",
    });

    expect(prepared.task).toBe("Precedent:\n- Run the focused validation.\n\nship");
    expect(prepared.attributedPrecedents).toEqual(["prec_validation"]);
    expect(prepared.candidateHints).toEqual([{ candidateId: "cand_untrusted", injection: "do not inject me" }]);
    expect(calls[0].args).toContain("--thread-id");
    expect(calls[0].args).toContain("thread-1");
  });

  it("records an outcome through Precedent hooks and fails open", async () => {
    const runner = vi.fn(async () => {
      throw new Error("precedent unavailable");
    });
    const bridge = createPrecedentBridge({ enabled: true }, runner);

    await expect(bridge.afterTurn({
      cwd: "/repo",
      threadId: "thread-1",
      task: "ship",
      success: true,
      response: "done",
      attributedPrecedents: ["prec_validation"],
    })).resolves.toBeUndefined();
  });

  it("records completed command evidence through validation hooks", async () => {
    const calls: Array<{ args: string[]; stdinJson?: unknown }> = [];
    const bridge = createPrecedentBridge({ enabled: true }, async (input) => {
      calls.push({ args: input.args, stdinJson: input.stdinJson });
      return {};
    });

    await bridge.observeTurnEvent({
      cwd: "/repo",
      threadId: "thread-1",
      attributedPrecedents: ["prec_validation"],
      event: {
        kind: "itemCompleted",
        threadId: "thread-1",
        turnId: "turn-1",
        itemId: "cmd-1",
        itemType: "commandExecution",
        text: null,
        status: "completed",
        command: "npm test",
        output: "pass",
        exitCode: 0,
        durationMs: 1234,
      },
    });

    expect(calls).toHaveLength(1);
    expect(calls[0].args).toEqual(["hook", "--state-dir", ".precedent", "--json"]);
    expect(calls[0].stdinJson).toMatchObject({
      schema_version: "precedent.v1",
      hook: "validation.after_run",
      command: "npm test",
      exitCode: 0,
      durationMs: 1234,
      stdout: "pass",
      stderr: "",
      attributedPrecedents: ["prec_validation"],
    });
  });

  it("records turn diff evidence through diff hooks", async () => {
    const calls: Array<{ args: string[]; stdinJson?: unknown }> = [];
    const bridge = createPrecedentBridge({ enabled: true }, async (input) => {
      calls.push({ args: input.args, stdinJson: input.stdinJson });
      return {};
    });

    await bridge.observeTurnEvent({
      cwd: "/repo",
      threadId: "thread-1",
      attributedPrecedents: ["prec_diff"],
      event: {
        kind: "turnDiffUpdated",
        threadId: "thread-1",
        turnId: "turn-1",
        diff: "diff --git a/a b/a",
      },
    });

    expect(calls[0].stdinJson).toMatchObject({
      schema_version: "precedent.v1",
      hook: "diff.after_edit",
      unifiedDiff: "diff --git a/a b/a",
      attributedPrecedents: ["prec_diff"],
    });
  });

  it("returns the original prompt when disabled", async () => {
    const bridge = createPrecedentBridge({ enabled: false });

    const prepared = await bridge.beforeTurn({
      cwd: "/repo",
      threadId: "thread-1",
      task: "ship",
    });

    expect(prepared.task).toBe("ship");
    expect(prepared.attributedPrecedents).toEqual([]);
  });
});
