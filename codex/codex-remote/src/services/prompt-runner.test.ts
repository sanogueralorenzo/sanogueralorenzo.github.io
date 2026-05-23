import { beforeEach, describe, expect, it, vi } from "vitest";
import {
  sendMessageWithoutResumeWithTimeoutContinuation,
  sendMessageWithTimeoutContinuation,
} from "../adapters/app-server/client.js";
import { createPromptRunner } from "./prompt-runner.js";
import { PrecedentBridge } from "./precedent-bridge.js";

vi.mock("../adapters/app-server/client.js", () => ({
  createAndSendFirstMessageWithTimeoutContinuation: vi.fn(),
  sendMessageWithoutResumeWithTimeoutContinuation: vi.fn(),
  sendMessageWithTimeoutContinuation: vi.fn(async (_threadId: string, text: string) => ({
    status: "completed",
    response: `done:${text}`,
  })),
}));

describe("createPromptRunner", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it("passes Precedent context into normal thread prompts and records outcomes", async () => {
    const sentMessages: string[] = [];
    const afterTurns: unknown[] = [];
    const bridge: PrecedentBridge = {
      beforeTurn: vi.fn(async () => ({
        task: "Precedent:\n- Run focused validation.\n\nship it",
        contextBlock: "Precedent:\n- Run focused validation.",
        candidateHints: [{ candidateId: "cand_untrusted" }],
        promotionTrials: [],
        attributedPrecedents: ["prec_validation"],
      })),
      beforeRetry: vi.fn(async () => ({ repairBlock: "", repairId: null })),
      observeTurnEvent: vi.fn(async () => {}),
      afterRetry: vi.fn(async () => {}),
      afterTurn: vi.fn(async (input) => {
        afterTurns.push(input);
      }),
    };
    const runner = createPromptRunner({
      store: { get: async () => "thread-1" } as never,
      pendingNewSessionChats: new Set(),
      getPendingNewSessionCwd: () => null,
      clearPendingNewSessionCwd: () => {},
      onThreadNotBound: async () => {},
      getConversationOptions: () => ({ cwd: "/repo" }),
      bindChatToThread: async () => {},
      requestApprovalFromTelegram: async () => "accept",
      precedentBridge: bridge,
    });

    await runner.runPromptThroughCodex(fakeContext(sentMessages), "chat-1", "ship it");

    expect(sendMessageWithTimeoutContinuation).toHaveBeenCalledWith(
      "thread-1",
      "Precedent:\n- Run focused validation.\n\nship it",
      expect.any(Object)
    );
    const runtimeOptions = vi.mocked(sendMessageWithTimeoutContinuation).mock.calls[0][2] as {
      onTurnEvent?: (event: Parameters<PrecedentBridge["observeTurnEvent"]>[0]["event"]) => void;
    };
    runtimeOptions.onTurnEvent?.({
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
      durationMs: 100,
    });
    expect(bridge.observeTurnEvent).toHaveBeenCalledWith({
      cwd: "/repo",
      threadId: "thread-1",
      attributedPrecedents: ["prec_validation"],
      event: expect.objectContaining({
        kind: "itemCompleted",
        command: "npm test",
        exitCode: 0,
      }),
    });
    expect(sentMessages).toEqual(["done:Precedent:\n- Run focused validation.\n\nship it"]);
    expect(afterTurns).toMatchObject([{
      cwd: "/repo",
      threadId: "thread-1",
      task: "ship it",
      response: "done:Precedent:\n- Run focused validation.\n\nship it",
      success: true,
      attributedPrecedents: ["prec_validation"],
    }]);
  });

  it("leaves prompts unchanged without a Precedent bridge", async () => {
    const sentMessages: string[] = [];
    const runner = createPromptRunner({
      store: { get: async () => "thread-1" } as never,
      pendingNewSessionChats: new Set(),
      getPendingNewSessionCwd: () => null,
      clearPendingNewSessionCwd: () => {},
      onThreadNotBound: async () => {},
      getConversationOptions: () => ({ cwd: "/repo" }),
      bindChatToThread: async () => {},
      requestApprovalFromTelegram: async () => "accept",
    });

    await runner.runPromptThroughCodex(fakeContext(sentMessages), "chat-1", "ship it");

    expect(sendMessageWithTimeoutContinuation).toHaveBeenCalledWith(
      "thread-1",
      "ship it",
      expect.any(Object)
    );
  });

  it("records failed outcomes when normal thread prompts fail", async () => {
    vi.mocked(sendMessageWithTimeoutContinuation).mockRejectedValueOnce(new Error("boom"));
    const sentMessages: string[] = [];
    const afterTurns: unknown[] = [];
    const bridge: PrecedentBridge = {
      beforeTurn: vi.fn(async () => ({
        task: "Precedent:\n- Run focused validation.\n\nship it",
        contextBlock: "Precedent:\n- Run focused validation.",
        candidateHints: [],
        promotionTrials: [],
        attributedPrecedents: ["prec_validation"],
      })),
      beforeRetry: vi.fn(async () => ({ repairBlock: "", repairId: null })),
      observeTurnEvent: vi.fn(async () => {}),
      afterRetry: vi.fn(async () => {}),
      afterTurn: vi.fn(async (input) => {
        afterTurns.push(input);
      }),
    };
    const runner = createPromptRunner({
      store: { get: async () => "thread-1" } as never,
      pendingNewSessionChats: new Set(),
      getPendingNewSessionCwd: () => null,
      clearPendingNewSessionCwd: () => {},
      onThreadNotBound: async () => {},
      getConversationOptions: () => ({ cwd: "/repo" }),
      bindChatToThread: async () => {},
      requestApprovalFromTelegram: async () => "accept",
      precedentBridge: bridge,
    });

    await runner.runPromptThroughCodex(fakeContext(sentMessages), "chat-1", "ship it");

    expect(afterTurns).toMatchObject([{
      cwd: "/repo",
      threadId: "thread-1",
      task: "ship it",
      response: "boom",
      success: false,
      attributedPrecedents: ["prec_validation"],
    }]);
    expect(sentMessages[0]).toContain("boom");
  });

  it("prepends repair context and records a retry receipt", async () => {
    const sentMessages: string[] = [];
    const afterRetries: unknown[] = [];
    const bridge: PrecedentBridge = {
      beforeTurn: vi.fn(async () => ({
        task: "Precedent:\n- Run focused validation.\n\nship it",
        contextBlock: "Precedent:\n- Run focused validation.",
        candidateHints: [],
        promotionTrials: [],
        attributedPrecedents: ["prec_validation"],
      })),
      beforeRetry: vi.fn(async () => ({
        repairBlock: "Precedent repair:\n- Re-run the focused validation.",
        repairId: "repair_123",
      })),
      observeTurnEvent: vi.fn(async () => {}),
      afterRetry: vi.fn(async (input) => {
        afterRetries.push(input);
      }),
      afterTurn: vi.fn(async () => {}),
    };
    const runner = createPromptRunner({
      store: { get: async () => "thread-1" } as never,
      pendingNewSessionChats: new Set(),
      getPendingNewSessionCwd: () => null,
      clearPendingNewSessionCwd: () => {},
      onThreadNotBound: async () => {},
      getConversationOptions: () => ({ cwd: "/repo" }),
      bindChatToThread: async () => {},
      requestApprovalFromTelegram: async () => "accept",
      precedentBridge: bridge,
    });

    await runner.runPromptThroughCodex(fakeContext(sentMessages), "chat-1", "ship it");

    expect(sendMessageWithTimeoutContinuation).toHaveBeenCalledWith(
      "thread-1",
      "Precedent repair:\n- Re-run the focused validation.\n\nPrecedent:\n- Run focused validation.\n\nship it",
      expect.any(Object)
    );
    expect(afterRetries).toMatchObject([{
      cwd: "/repo",
      threadId: "thread-1",
      repairId: "repair_123",
      attributedPrecedents: ["prec_validation"],
    }]);
  });

  it("reuses prepared repair context when falling back from a missing rollout", async () => {
    vi.mocked(sendMessageWithTimeoutContinuation).mockRejectedValueOnce(new Error("no rollout found for thread id thread-1"));
    vi.mocked(sendMessageWithoutResumeWithTimeoutContinuation).mockResolvedValueOnce({
      status: "completed",
      response: "fallback done",
    });
    const sentMessages: string[] = [];
    const bridge: PrecedentBridge = {
      beforeTurn: vi.fn(async () => ({
        task: "Precedent:\n- Run focused validation.\n\nship it",
        contextBlock: "Precedent:\n- Run focused validation.",
        candidateHints: [],
        promotionTrials: [],
        attributedPrecedents: ["prec_validation"],
      })),
      beforeRetry: vi.fn(async () => ({
        repairBlock: "Precedent repair:\n- Re-run the focused validation.",
        repairId: "repair_123",
      })),
      observeTurnEvent: vi.fn(async () => {}),
      afterRetry: vi.fn(async () => {}),
      afterTurn: vi.fn(async () => {}),
    };
    const runner = createPromptRunner({
      store: { get: async () => "thread-1" } as never,
      pendingNewSessionChats: new Set(),
      getPendingNewSessionCwd: () => null,
      clearPendingNewSessionCwd: () => {},
      onThreadNotBound: async () => {},
      getConversationOptions: () => ({ cwd: "/repo" }),
      bindChatToThread: async () => {},
      requestApprovalFromTelegram: async () => "accept",
      precedentBridge: bridge,
    });

    await runner.runPromptThroughCodex(fakeContext(sentMessages), "chat-1", "ship it");

    expect(bridge.beforeRetry).toHaveBeenCalledTimes(1);
    expect(sendMessageWithoutResumeWithTimeoutContinuation).toHaveBeenCalledWith(
      "thread-1",
      "Precedent repair:\n- Re-run the focused validation.\n\nPrecedent:\n- Run focused validation.\n\nship it",
      expect.any(Object)
    );
    expect(sentMessages).toEqual(["fallback done"]);
  });
});

function fakeContext(sentMessages: string[]) {
  return {
    chat: { id: 123 },
    api: {
      sendMessage: async (_chatId: number, message: string) => {
        sentMessages.push(message);
      },
    },
    reply: async (message: string) => {
      sentMessages.push(message);
    },
  } as never;
}
