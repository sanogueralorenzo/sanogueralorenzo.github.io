import { describe, expect, it } from "vitest";

import type {
  ClientRequest,
  ServerNotification,
  ServerRequest,
} from "./generated/index.js";

describe("generated app-server protocol types", () => {
  it("covers the request and notification shapes used by codex-remote", () => {
    type InitializeRequest = Extract<ClientRequest, { method: "initialize" }>;
    type CommandApprovalRequest = Extract<
      ServerRequest,
      { method: "item/commandExecution/requestApproval" }
    >;
    type TurnCompleted = Extract<ServerNotification, { method: "turn/completed" }>;

    const initialize = {
      id: 1,
      method: "initialize",
      params: {
        clientInfo: {
          name: "telegram-codex-remote",
          title: null,
          version: "1.0",
        },
        capabilities: {
          experimentalApi: true,
        },
      },
    } satisfies InitializeRequest;

    const approval = {
      id: 2,
      method: "item/commandExecution/requestApproval",
      params: {
        threadId: "thread-1",
        turnId: "turn-1",
        itemId: "item-1",
        startedAtMs: 0,
        command: "git status",
        cwd: "/tmp/project",
      },
    } satisfies CommandApprovalRequest;

    const completed = {
      method: "turn/completed",
      params: {
        threadId: "thread-1",
        turn: {
          id: "turn-1",
          items: [],
          itemsView: "notLoaded",
          status: "completed",
          startedAt: null,
          completedAt: null,
          durationMs: null,
          error: null,
        },
      },
    } satisfies TurnCompleted;

    expect(initialize.method).toBe("initialize");
    expect(approval.method).toBe("item/commandExecution/requestApproval");
    expect(completed.method).toBe("turn/completed");
  });
});
