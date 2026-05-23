import { beforeEach, describe, expect, it, vi } from "vitest";
import {
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
