import process from "node:process";

export type ApprovalPolicy = "never" | "on-request" | "on-failure" | "untrusted";
export type SandboxMode = "read-only" | "workspace-write" | "danger-full-access";
export type ApprovalDecision = "accept" | "acceptForSession" | "decline" | "cancel";

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
export const CODEXHUB_BIN = process.env.CODEXHUB_BIN?.trim() || "codexhub";
export const THREAD_LIST_SOURCE_KINDS = ["vscode", "cli", "appServer"] as const;

// Keep transport-side policy in the app-server stream itself; clients focus on rendering.
export const DEFAULT_OPT_OUT_NOTIFICATION_METHODS = [
  "item/reasoning/summaryTextDelta",
  "item/reasoning/summaryPartAdded",
  "item/reasoning/textDelta",
  "item/plan/delta",
  "turn/plan/updated",
  "rawResponseItem/completed"
] as const;
