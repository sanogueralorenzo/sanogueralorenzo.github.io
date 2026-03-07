import { ApprovalDecision, ApprovalRequest } from "../adapters/app-server-client.js";
import { PromptContext } from "./context.js";
import { approvalKeyboard, parseApprovalDecisionText, quickActionsKeyboard } from "./keyboards.js";
import { limitTelegramText } from "../services/voice.js";

type PendingApproval = {
  resolve: (decision: ApprovalDecision) => void;
  timeout: NodeJS.Timeout;
};

type ApprovalServiceDeps = {
  defaultApprovalDecision: ApprovalDecision;
  timeoutMs: number;
};

export function createApprovalService(deps: ApprovalServiceDeps) {
  const pendingApprovals = new Map<string, PendingApproval>();

  async function requestApprovalFromTelegram(
    ctx: PromptContext,
    chatId: string,
    request: ApprovalRequest
  ): Promise<ApprovalDecision> {
    const prompt = formatApprovalPrompt(request);

    const existing = pendingApprovals.get(chatId);
    if (existing) {
      clearTimeout(existing.timeout);
      pendingApprovals.delete(chatId);
      existing.resolve(deps.defaultApprovalDecision);
    }

    const decisionPromise = new Promise<ApprovalDecision>((resolve) => {
      const timeout = setTimeout(() => {
        pendingApprovals.delete(chatId);
        resolve(deps.defaultApprovalDecision);
      }, deps.timeoutMs);

      pendingApprovals.set(chatId, {
        resolve,
        timeout
      });
    });

    try {
      await ctx.api.sendMessage(ctx.chat.id, limitTelegramText(prompt), { reply_markup: approvalKeyboard() });
    } catch {
      const pending = pendingApprovals.get(chatId);
      if (pending) {
        clearTimeout(pending.timeout);
        pendingApprovals.delete(chatId);
      }
      return deps.defaultApprovalDecision;
    }

    return decisionPromise;
  }

  async function resolveApprovalFromText(ctx: PromptContext, chatId: string, text: string): Promise<boolean> {
    const pending = pendingApprovals.get(chatId);
    if (!pending) {
      return false;
    }

    const decision = parseApprovalDecisionText(text);
    if (!decision) {
      return false;
    }

    clearTimeout(pending.timeout);
    pendingApprovals.delete(chatId);
    pending.resolve(decision);
    await ctx.reply("Approval sent", { reply_markup: quickActionsKeyboard() });
    return true;
  }

  return {
    requestApprovalFromTelegram,
    resolveApprovalFromText
  };
}

function formatApprovalPrompt(request: ApprovalRequest): string {
  const lines = [
    request.method === "item/fileChange/requestApproval"
      ? "Approval needed: file changes"
      : "Approval needed: command execution"
  ];

  if (request.command) {
    lines.push(`Command: ${request.command}`);
  }
  if (request.cwd) {
    lines.push(`Folder: ${request.cwd}`);
  }
  if (request.reason) {
    lines.push(`Reason: ${request.reason}`);
  }
  lines.push("", "Choose an action:");
  return lines.join("\n");
}
