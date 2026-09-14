import { describe, expect, it } from "vitest";
import { createUserInputService } from "./user-input.js";

describe("createUserInputService", () => {
  it("collects option and free-form answers in order", async () => {
    const sent: string[] = [];
    const service = createUserInputService(10_000);
    const context = fakeContext(sent);
    const answersPromise = service.requestUserInputFromTelegram(context, "123", {
      threadId: "thread-1",
      turnId: "turn-1",
      itemId: "item-1",
      isBlocking: true,
      autoResolutionMs: null,
      questions: [
        {
          id: "choice",
          header: "Choice",
          question: "Pick one",
          isOther: false,
          isSecret: false,
          options: [
            { label: "Alpha", description: "First" },
            { label: "Beta", description: "Second" },
          ],
        },
        {
          id: "details",
          header: "Details",
          question: "What should change?",
          isOther: false,
          isSecret: false,
          options: null,
        },
      ],
    });

    expect(service.hasPendingUserInput("123")).toBe(true);
    await service.resolveUserInputFromText(context, "123", "Alpha");
    await service.resolveUserInputFromText(context, "123", "Make it faster");

    await expect(answersPromise).resolves.toEqual({
      choice: { answers: ["Alpha"] },
      details: { answers: ["Make it faster"] },
    });
    expect(service.hasPendingUserInput("123")).toBe(false);
    expect(sent.join("\n")).toContain("Pick one");
    expect(sent.join("\n")).toContain("What should change?");
  });

  it("rejects invalid choices without advancing the question", async () => {
    const sent: string[] = [];
    const service = createUserInputService(10_000);
    const context = fakeContext(sent);
    const answersPromise = service.requestUserInputFromTelegram(context, "123", {
      threadId: "thread-1",
      turnId: "turn-1",
      itemId: "item-1",
      isBlocking: true,
      autoResolutionMs: null,
      questions: [
        {
          id: "choice",
          header: "Choice",
          question: "Pick one",
          isOther: false,
          isSecret: false,
          options: [{ label: "Alpha", description: "First" }],
        },
      ],
    });

    await service.resolveUserInputFromText(context, "123", "Invalid");
    expect(service.hasPendingUserInput("123")).toBe(true);

    await service.resolveUserInputFromText(context, "123", "Alpha");
    await expect(answersPromise).resolves.toEqual({
      choice: { answers: ["Alpha"] },
    });
  });
});

function fakeContext(sent: string[]) {
  return {
    chat: { id: 123 },
    api: {
      sendMessage: async (_chatId: number, text: string) => {
        sent.push(text);
      },
    },
  } as never;
}
