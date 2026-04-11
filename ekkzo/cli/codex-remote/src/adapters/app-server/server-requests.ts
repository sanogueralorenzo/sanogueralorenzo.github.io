import {
  ApprovalDecision,
  ApprovalRequest,
  TurnRuntimeOptions,
} from "./types.js";
import { asArray, asObject, getString } from "./json.js";
import { JsonRpcRequest } from "./protocol.js";

export async function handleServerRequest(
  request: JsonRpcRequest,
  runtimeOptions?: TurnRuntimeOptions
): Promise<unknown> {
  switch (request.method) {
    case "execCommandApproval":
    case "applyPatchApproval": {
      const decision = await requestDecisionFromHandler(
        toLegacyApprovalRequest(request.method, request.params),
        runtimeOptions
      );
      return { decision: mapLegacyApprovalDecision(decision) };
    }
    case "item/commandExecution/requestApproval":
    case "item/fileChange/requestApproval": {
      const decision = await requestDecisionFromHandler(
        toV2ApprovalRequest(request.method, request.params),
        runtimeOptions
      );
      return { decision };
    }
    case "item/tool/requestUserInput":
      return {
        answers: buildEmptyToolInputAnswers(asArray(asObject(request.params).questions)),
      };
    case "item/tool/call":
      return {
        success: false,
        contentItems: [
          {
            type: "inputText",
            text: "Dynamic tool calls are not supported by this Telegram codex-remote runtime.",
          },
        ],
      };
    case "account/chatgptAuthTokens/refresh":
      throw new Error("ChatGPT auth token refresh is not supported in this codex-remote runtime.");
    default:
      throw new Error(`Unsupported server request method: ${request.method}`);
  }
}

async function requestDecisionFromHandler(
  request: ApprovalRequest | null,
  runtimeOptions?: TurnRuntimeOptions
): Promise<ApprovalDecision> {
  if (!request || !runtimeOptions?.approvalHandler) {
    return "decline";
  }

  try {
    return await runtimeOptions.approvalHandler(request);
  } catch {
    return "decline";
  }
}

function buildEmptyToolInputAnswers(questions: unknown[]): Record<string, { answers: string[] }> {
  const answers: Record<string, { answers: string[] }> = {};
  for (const question of questions) {
    const questionId = getString(asObject(question).id);
    if (!questionId) {
      continue;
    }
    answers[questionId] = { answers: [] };
  }
  return answers;
}

function toV2ApprovalRequest(
  method: "item/commandExecution/requestApproval" | "item/fileChange/requestApproval",
  paramsValue: unknown
): ApprovalRequest | null {
  const params = asObject(paramsValue);
  const threadId = getString(params.threadId);
  const turnId = getString(params.turnId);
  const itemId = getString(params.itemId);
  if (!threadId || !turnId || !itemId) {
    return null;
  }

  return {
    method,
    threadId,
    turnId,
    itemId,
    approvalId: getString(params.approvalId),
    reason: getString(params.reason),
    command: getString(params.command),
    cwd: getString(params.cwd),
  };
}

function toLegacyApprovalRequest(
  method: "execCommandApproval" | "applyPatchApproval",
  paramsValue: unknown
): ApprovalRequest | null {
  const params = asObject(paramsValue);
  const threadId = getString(params.conversationId);
  const callId = getString(params.callId);
  if (!threadId || !callId) {
    return null;
  }

  let command: string | null = null;
  const cmd = params.command;
  if (Array.isArray(cmd)) {
    const parts = cmd.filter((part): part is string => typeof part === "string");
    if (parts.length) {
      command = parts.join(" ");
    }
  }

  return {
    method:
      method === "execCommandApproval"
        ? "item/commandExecution/requestApproval"
        : "item/fileChange/requestApproval",
    threadId,
    turnId: callId,
    itemId: callId,
    approvalId: getString(params.approvalId),
    reason: getString(params.reason),
    command,
    cwd: getString(params.cwd),
  };
}

function mapLegacyApprovalDecision(
  decision: ApprovalDecision
): "approved" | "approved_for_session" | "denied" | "abort" {
  switch (decision) {
    case "accept":
      return "approved";
    case "acceptForSession":
      return "approved_for_session";
    case "cancel":
      return "abort";
    default:
      return "denied";
  }
}
