import process from "node:process";

import type { CommandExecutionApprovalDecision } from "./generated/v2/CommandExecutionApprovalDecision.js";
import type { FileChangeApprovalDecision } from "./generated/v2/FileChangeApprovalDecision.js";
import type { AskForApproval } from "./generated/v2/AskForApproval.js";
import type { SandboxMode as GeneratedSandboxMode } from "./generated/v2/SandboxMode.js";
import type { ThreadSourceKind } from "./generated/v2/ThreadSourceKind.js";

export type ApprovalPolicy = Extract<AskForApproval, string>;
export type SandboxMode = GeneratedSandboxMode;
export type ApprovalDecision = Extract<
  CommandExecutionApprovalDecision | FileChangeApprovalDecision,
  "accept" | "acceptForSession" | "decline" | "cancel"
>;

export type ApprovalRequest = {
  method: "item/commandExecution/requestApproval" | "item/fileChange/requestApproval";
  threadId: string;
  turnId: string;
  itemId: string;
  approvalId: string | null;
  reason: string | null;
  command: string | null;
  cwd: string | null;
};

export type TurnProgressEvent =
  | {
      kind: "itemStarted";
      threadId: string;
      turnId: string;
      itemId: string;
      itemType: string;
      command: string | null;
    }
  | {
      kind: "itemCompleted";
      threadId: string;
      turnId: string;
      itemId: string;
      itemType: string;
      text: string | null;
      status: string | null;
      command: string | null;
      output: string | null;
      exitCode: number | null;
      durationMs: number | null;
    }
  | {
      kind: "turnDiffUpdated";
      threadId: string;
      turnId: string;
      diff: string;
    }
  | {
      kind: "agentDelta" | "commandOutputDelta";
      threadId: string;
      turnId: string;
      itemId: string;
      itemType: string;
      text: string;
    };

export type TurnRuntimeOptions = {
  approvalHandler?: (request: ApprovalRequest) => Promise<ApprovalDecision>;
  onTurnEvent?: (event: TurnProgressEvent) => void;
};

export type ConversationOptions = {
  cwd: string;
  model?: string;
  approvalPolicy?: ApprovalPolicy;
  sandboxMode?: SandboxMode;
  networkAccessEnabled?: boolean | null;
  skipGitRepoCheck?: boolean | null;
};

export type ThreadSummary = {
  id: string;
  cwd: string;
  preview: string;
  createdAt: number;
  updatedAt: number;
  path: string | null;
  source: string;
};

export type TurnCompletion = {
  response: string;
};

export type TimedTurnResult =
  | {
      status: "completed";
      response: string;
    }
  | {
      status: "timed_out";
      completion: Promise<TurnCompletion>;
    };

export type TimedCreateTurnResult =
  | {
      status: "completed";
      threadId: string;
      response: string;
    }
  | {
      status: "timed_out";
      threadId: string;
      completion: Promise<TurnCompletion>;
    };

export const TURN_TIMEOUT_MS = 5 * 60 * 1000;
export const CODEX_BIN = process.env.CODEX_BIN?.trim() || "codex";
export const THREAD_LIST_SOURCE_KINDS = ["vscode", "cli", "appServer"] as const satisfies ReadonlyArray<ThreadSourceKind>;

// Keep transport-side policy in the app-server stream itself; clients focus on rendering.
export const DEFAULT_OPT_OUT_NOTIFICATION_METHODS = [
  "item/reasoning/summaryTextDelta",
  "item/reasoning/summaryPartAdded",
  "item/reasoning/textDelta",
  "item/plan/delta",
  "turn/plan/updated",
  "rawResponseItem/completed"
] as const;
