import { describe, expect, it } from "vitest";

import { handleServerRequest } from "./server-requests.js";

describe("handleServerRequest", () => {
  it("maps command approval requests through the approval handler", async () => {
    const result = await handleServerRequest(
      {
        id: 1,
        method: "item/commandExecution/requestApproval",
        params: {
          threadId: "thread-1",
          turnId: "turn-1",
          itemId: "item-1",
          startedAtMs: 0,
          command: "git status",
          cwd: "/tmp/project",
        },
      },
      {
        approvalHandler: async (request) => {
          expect(request).toMatchObject({
            method: "item/commandExecution/requestApproval",
            threadId: "thread-1",
            turnId: "turn-1",
            itemId: "item-1",
            command: "git status",
            cwd: "/tmp/project",
          });
          return "acceptForSession";
        },
      }
    );

    expect(result).toEqual({ decision: "acceptForSession" });
  });

  it("rejects unsupported legacy approval requests", async () => {
    await expect(
      handleServerRequest({
        id: 1,
        method: "execCommandApproval",
        params: {
          conversationId: "thread-1",
          callId: "call-1",
          approvalId: null,
          command: ["git", "status"],
          cwd: "/tmp/project",
          reason: null,
          parsedCmd: [],
        },
      })
    ).rejects.toThrow("Unsupported server request method: execCommandApproval");
  });

  it("returns empty answers for requestUserInput prompts", async () => {
    const result = await handleServerRequest({
      id: 1,
      method: "item/tool/requestUserInput",
      params: {
        threadId: "thread-1",
        turnId: "turn-1",
        itemId: "item-1",
        questions: [
          {
            id: "q1",
            header: "One",
            question: "Question one?",
            isOther: false,
            isSecret: false,
            options: null,
          },
          {
            id: "q2",
            header: "Two",
            question: "Question two?",
            isOther: false,
            isSecret: false,
            options: null,
          },
        ],
      },
    });

    expect(result).toEqual({
      answers: {
        q1: { answers: [] },
        q2: { answers: [] },
      },
    });
  });
});
