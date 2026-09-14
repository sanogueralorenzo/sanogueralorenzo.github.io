import {
  ApprovalDecision,
  ApprovalRequest,
  TurnRuntimeOptions,
  UserInputAnswers,
  UserInputRequest,
} from "./types.js";
import { JsonRpcRequest } from "./protocol.js";

export async function handleServerRequest(
  request: JsonRpcRequest,
  runtimeOptions?: TurnRuntimeOptions
): Promise<unknown> {
  switch (request.method) {
    case "item/commandExecution/requestApproval": {
      const decision = await requestDecisionFromHandler(
        {
          method: request.method,
          threadId: request.params.threadId,
          turnId: request.params.turnId,
          itemId: request.params.itemId,
          approvalId: request.params.approvalId ?? null,
          reason: request.params.reason ?? null,
          command: request.params.command ?? null,
          cwd: request.params.cwd ?? null,
        },
        runtimeOptions
      );
      return { decision };
    }
    case "item/fileChange/requestApproval": {
      const decision = await requestDecisionFromHandler(
        {
          method: request.method,
          threadId: request.params.threadId,
          turnId: request.params.turnId,
          itemId: request.params.itemId,
          approvalId: null,
          reason: request.params.reason ?? null,
          command: null,
          cwd: null,
        },
        runtimeOptions
      );
      return { decision };
    }
    case "item/tool/requestUserInput": {
      const answers = await requestUserInputFromHandler(request.params, runtimeOptions);
      return { answers };
    }
    case "item/tool/call":
      return {
        success: false,
        contentItems: [
          {
            type: "inputText",
            text: "Dynamic tool calls are not supported by this codexbot runtime.",
          },
        ],
      };
    case "account/chatgptAuthTokens/refresh":
      throw new Error("ChatGPT auth token refresh is not supported in this codexbot runtime.");
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

async function requestUserInputFromHandler(
  request: UserInputRequest,
  runtimeOptions?: TurnRuntimeOptions
): Promise<UserInputAnswers> {
  if (!runtimeOptions?.requestUserInputHandler) {
    return buildEmptyToolInputAnswers(request.questions);
  }

  return runtimeOptions.requestUserInputHandler(request);
}

function buildEmptyToolInputAnswers(questions: Array<{ id: string }>): UserInputAnswers {
  const answers: UserInputAnswers = {};
  for (const question of questions) {
    answers[question.id] = { answers: [] };
  }
  return answers;
}
