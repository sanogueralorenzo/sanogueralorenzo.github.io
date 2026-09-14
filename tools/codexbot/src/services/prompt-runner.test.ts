import { beforeEach, describe, expect, it, vi } from "vitest";
import {
  sendMessageWithoutResumeWithTimeoutContinuation,
  sendMessageWithTimeoutContinuation,
} from "../adapters/app-server/client.js";
import { createPromptRunner } from "./prompt-runner.js";

const CODEXBOT_FINAL_INSTRUCTION = "Be concise; include outcome, validation, blockers if relevant; no extra explanation unless asked.";

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
    vi.mocked(sendMessageWithTimeoutContinuation).mockReset();
    vi.mocked(sendMessageWithoutResumeWithTimeoutContinuation).mockReset();
    vi.mocked(sendMessageWithTimeoutContinuation).mockImplementation(async (_threadId: string, text: string) => ({
      status: "completed",
      response: `done:${text}`,
    }));
  });

  it("adds the codexbot final instruction", async () => {
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
      codexbotPrompt("ship it"),
      expect.any(Object)
    );
  });

  it("sends generated image paths after the final text", async () => {
    vi.mocked(sendMessageWithTimeoutContinuation).mockResolvedValueOnce({
      status: "completed",
      response: "generated",
      imagePaths: ["/tmp/generated.png"],
    });
    const sentMessages: string[] = [];
    const sentPhotos: string[] = [];
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

    await runner.runPromptThroughCodex(fakeContext(sentMessages, sentPhotos), "chat-1", "draw it");

    expect(sentMessages).toEqual(["generated"]);
    expect(sentPhotos).toEqual(["generated.png"]);
  });

  it("falls back to the generated image path when Telegram upload fails", async () => {
    vi.mocked(sendMessageWithTimeoutContinuation).mockResolvedValueOnce({
      status: "completed",
      response: "generated",
      imagePaths: ["/tmp/generated.png"],
    });
    const sentMessages: string[] = [];
    const sentPhotos: string[] = [];
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

    await runner.runPromptThroughCodex(fakeContext(sentMessages, sentPhotos, true), "chat-1", "draw it");

    expect(sentPhotos).toEqual(["generated.png"]);
    expect(sentMessages).toEqual([
      "generated",
      "Image generated but Telegram upload failed:\n/tmp/generated.png",
    ]);
  });

  it("serializes prompts that target the same Codex thread until completion", async () => {
    const firstCompletion = deferred<{ response: string }>();
    vi.mocked(sendMessageWithTimeoutContinuation).mockResolvedValueOnce({
      status: "timed_out",
      completion: firstCompletion.promise,
    });
    vi.mocked(sendMessageWithTimeoutContinuation).mockResolvedValueOnce({
      status: "completed",
      response: "second done",
    });
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

    const firstRun = runner.runPromptThroughCodex(fakeContext(sentMessages), "chat-1", "first");
    await flushPromises();
    const secondRun = runner.runPromptThroughCodex(fakeContext(sentMessages), "chat-2", "second");
    await flushPromises();

    expect(sendMessageWithTimeoutContinuation).toHaveBeenCalledTimes(1);

    firstCompletion.resolve({ response: "first done" });
    await Promise.all([firstRun, secondRun]);

    expect(sendMessageWithTimeoutContinuation).toHaveBeenNthCalledWith(
      2,
      "thread-1",
      codexbotPrompt("second"),
      expect.any(Object)
    );
    expect(sentMessages).toEqual(["first done", "second done"]);
  });

  it("allows prompts for different Codex threads to run independently", async () => {
    const firstCompletion = deferred<{ response: string }>();
    vi.mocked(sendMessageWithTimeoutContinuation).mockImplementationOnce(async () => ({
      status: "timed_out",
      completion: firstCompletion.promise,
    }));
    vi.mocked(sendMessageWithTimeoutContinuation).mockImplementationOnce(async () => ({
      status: "completed",
      response: "second done",
    }));
    const sentMessages: string[] = [];
    const runner = createPromptRunner({
      store: { get: async (chatId: string) => chatId === "chat-1" ? "thread-1" : "thread-2" } as never,
      pendingNewSessionChats: new Set(),
      getPendingNewSessionCwd: () => null,
      clearPendingNewSessionCwd: () => {},
      onThreadNotBound: async () => {},
      getConversationOptions: () => ({ cwd: "/repo" }),
      bindChatToThread: async () => {},
      requestApprovalFromTelegram: async () => "accept",
    });

    const firstRun = runner.runPromptThroughCodex(fakeContext(sentMessages), "chat-1", "first");
    await flushPromises();
    const secondRun = runner.runPromptThroughCodex(fakeContext(sentMessages), "chat-2", "second");
    await secondRun;

    expect(sendMessageWithTimeoutContinuation).toHaveBeenCalledTimes(2);
    expect(sentMessages).toEqual(["second done"]);

    firstCompletion.resolve({ response: "first done" });
    await firstRun;

    expect(sentMessages).toEqual(["second done", "first done"]);
  });

});

function codexbotPrompt(text: string): string {
  return `${text}\n\n${CODEXBOT_FINAL_INSTRUCTION}`;
}

function fakeContext(sentMessages: string[], sentPhotos: string[] = [], failPhoto = false) {
  return {
    chat: { id: 123 },
    api: {
      sendMessage: async (_chatId: number, message: string) => {
        sentMessages.push(message);
      },
      sendPhoto: async (_chatId: number, photo: { filename?: string } | string) => {
        sentPhotos.push(typeof photo === "string" ? photo : photo.filename ?? "");
        if (failPhoto) {
          throw new Error("upload failed");
        }
      },
    },
    reply: async (message: string) => {
      sentMessages.push(message);
    },
  } as never;
}

function deferred<T>() {
  let resolve: (value: T) => void = () => {};
  let reject: (error: unknown) => void = () => {};
  const promise = new Promise<T>((resolvePromise, rejectPromise) => {
    resolve = resolvePromise;
    reject = rejectPromise;
  });

  return { promise, resolve, reject };
}

async function flushPromises(): Promise<void> {
  await new Promise((resolve) => {
    setImmediate(resolve);
  });
}
