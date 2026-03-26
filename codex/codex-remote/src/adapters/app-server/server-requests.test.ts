import { describe, expect, it } from "vitest";

import { handleServerRequest } from "./server-requests.js";

describe("handleServerRequest", () => {
  it("maps legacy approval requests through the approval handler", async () => {
    const result = await handleServerRequest(
      {
        id: 1,
        method: "execCommandApproval",
        params: {
          conversationId: "thread-1",
          callId: "call-1",
          command: ["git", "status"],
          cwd: "/tmp/project",
        },
      },
      {
        approvalHandler: async (request) => {
          expect(request).toMatchObject({
            method: "item/commandExecution/requestApproval",
            threadId: "thread-1",
            turnId: "call-1",
            itemId: "call-1",
            command: "git status",
            cwd: "/tmp/project",
          });
          return "acceptForSession";
        },
      }
    );

    expect(result).toEqual({ decision: "approved_for_session" });
  });

  it("returns empty answers for requestUserInput prompts", async () => {
    const result = await handleServerRequest({
      id: 1,
      method: "item/tool/requestUserInput",
      params: {
        questions: [{ id: "q1" }, { id: "q2" }],
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
