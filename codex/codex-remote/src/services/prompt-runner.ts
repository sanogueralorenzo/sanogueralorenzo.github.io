import type {
  ApprovalDecision,
  ApprovalPolicy,
  ApprovalRequest,
  SandboxMode,
  TurnProgressEvent,
} from "../adapters/app-server/client.js";
import {
  createAndSendFirstMessageWithTimeoutContinuation,
  sendMessageWithoutResumeWithTimeoutContinuation,
  sendMessageWithTimeoutContinuation,
} from "../adapters/app-server/client.js";
import { BindingStore } from "../adapters/binding-store.js";
import { formatFailure } from "../bot/messages.js";
import { PromptContext } from "../bot/context.js";
import { sendTextChunks } from "../shared/telegram-text.js";
import { PrecedentBridge } from "./precedent-bridge.js";

type ConversationOptions = {
  cwd: string;
  model?: string;
  approvalPolicy?: ApprovalPolicy;
  sandboxMode?: SandboxMode;
  networkAccessEnabled?: boolean | null;
  skipGitRepoCheck?: boolean | null;
};

type TimedTurnLike =
  | { status: "completed"; response: string }
  | { status: "timed_out"; completion: Promise<{ response: string }> };

type PromptTurnRuntimeOptions = {
  approvalHandler: (request: ApprovalRequest) => Promise<ApprovalDecision>;
  onTurnEvent?: (event: TurnProgressEvent) => void;
};

type PromptRunnerDeps = {
  store: BindingStore;
  pendingNewSessionChats: Set<string>;
  getPendingNewSessionCwd: (chatId: string) => string | null;
  clearPendingNewSessionCwd: (chatId: string) => void;
  onThreadNotBound: (ctx: PromptContext, chatId: string) => Promise<void>;
  getConversationOptions: () => ConversationOptions;
  bindChatToThread: (chatId: string, threadId: string) => Promise<void>;
  requestApprovalFromTelegram: (ctx: PromptContext, chatId: string, request: ApprovalRequest) => Promise<ApprovalDecision>;
  precedentBridge?: PrecedentBridge;
};

export function createPromptRunner(deps: PromptRunnerDeps) {
  async function runPromptThroughCodex(ctx: PromptContext, chatId: string, text: string): Promise<void> {
    const threadId = await deps.store.get(chatId);
    const finalOutputRelay = createFinalOutputRelay((message) => ctx.api.sendMessage(ctx.chat.id, message));
    const runtimeOptions: PromptTurnRuntimeOptions = {
      approvalHandler: (request: ApprovalRequest) => deps.requestApprovalFromTelegram(ctx, chatId, request),
    };
    const precedentBridge = deps.precedentBridge;
    let failurePrecedent: PreparedPrecedentTurn | null = null;
    const finalizeTurn = async (
      turn: TimedTurnLike,
      precedent: PreparedPrecedentTurn | null,
      observer: PrecedentTurnObserver | null
    ): Promise<void> => {
      await replyFromTimedTurn(turn, finalOutputRelay, async (response) => {
        let finalResponse = response;
        let finalPrecedent = precedent;
        if (precedentBridge && precedent) {
          const repaired = await repairCurrentTurn(response, text, precedent, observer, runtimeOptionsFor);
          finalResponse = repaired.response;
          finalPrecedent = repaired.precedent;
          await precedentBridge.afterTurn({
            cwd: finalPrecedent.cwd,
            threadId: finalPrecedent.threadId,
            task: text,
            response: finalResponse,
            success: true,
            attributedPrecedents: finalPrecedent.attributedPrecedents,
          });
          await recordRepairReceipt(finalPrecedent);
        }
        return finalResponse;
      });
    };
    const runtimeOptionsFor = (
      precedent: PreparedPrecedentTurn | null,
      observer: PrecedentTurnObserver | null
    ): PromptTurnRuntimeOptions => {
      if (!precedentBridge || !precedent) {
        return runtimeOptions;
      }

      return {
        ...runtimeOptions,
        onTurnEvent: (event) => {
          const observation = precedentBridge.observeTurnEvent({
            cwd: precedent.cwd,
            threadId: precedent.threadId,
            event,
            attributedPrecedents: precedent.attributedPrecedents,
          });
          observer?.observations.push(observation);
          void observation;
        },
      };
    };

    try {
      if (!threadId) {
        if (deps.pendingNewSessionChats.has(chatId)) {
          const options = deps.getConversationOptions();
          const selectedCwd = deps.getPendingNewSessionCwd(chatId);
          if (selectedCwd) {
            options.cwd = selectedCwd;
          }
          const initialized = await createAndSendFirstMessageWithTimeoutContinuation(options, text, runtimeOptions);
          await deps.bindChatToThread(chatId, initialized.threadId);
          deps.pendingNewSessionChats.delete(chatId);
          deps.clearPendingNewSessionCwd(chatId);
          await finalizeTurn(initialized, null, null);
          return;
        }

        await deps.onThreadNotBound(ctx, chatId);
        return;
      }

      const precedent = await preparePrecedentTurn(threadId, text);
      failurePrecedent = precedent;
      const observer = createPrecedentTurnObserver();
      try {
        const turn = await sendMessageWithTimeoutContinuation(threadId, precedent.text, runtimeOptionsFor(precedent, observer));
        await finalizeTurn(turn, precedent, observer);
        failurePrecedent = null;
        return;
      } catch (error) {
        if (!isNoRolloutFoundError(error)) {
          throw error;
        }
      }

      try {
        const firstTurn = await sendMessageWithoutResumeWithTimeoutContinuation(threadId, precedent.text, runtimeOptionsFor(precedent, observer));
        await finalizeTurn(firstTurn, precedent, observer);
        failurePrecedent = null;
        return;
      } catch {
        failurePrecedent = null;
        await recoverFromUnavailableThread(chatId, text, runtimeOptions, finalOutputRelay);
        return;
      }
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      await recordFailedPrecedentTurn(failurePrecedent, text, message);
      await ctx.reply(formatFailure("Codex error.", message));
    }
  }

  async function repairCurrentTurn(
    response: string,
    task: string,
    precedent: PreparedPrecedentTurn,
    observer: PrecedentTurnObserver | null,
    runtimeOptionsForTurn: (
      precedent: PreparedPrecedentTurn | null,
      observer: PrecedentTurnObserver | null
    ) => PromptTurnRuntimeOptions
  ): Promise<{ response: string; precedent: PreparedPrecedentTurn }> {
    if (!deps.precedentBridge || precedent.repair) {
      return { response, precedent };
    }

    await settlePrecedentObservations(observer);
    const beforeRetry = await deps.precedentBridge.beforeRetry({
      cwd: precedent.cwd,
      threadId: precedent.threadId,
      task,
      attributedPrecedents: precedent.attributedPrecedents,
    });
    if (!beforeRetry.repairBlock || !beforeRetry.repairId) {
      return { response, precedent };
    }

    const repairPrecedent: PreparedPrecedentTurn = {
      ...precedent,
      text: beforeRetry.repairBlock,
      repair: {
        repairBlock: beforeRetry.repairBlock,
        repairId: beforeRetry.repairId,
      },
    };
    const repairObserver = createPrecedentTurnObserver();

    try {
      const repairedTurn = await sendMessageWithTimeoutContinuation(
        precedent.threadId,
        beforeRetry.repairBlock,
        runtimeOptionsForTurn(repairPrecedent, repairObserver)
      );
      const repairedResponse = await responseFromTimedTurn(repairedTurn);
      await settlePrecedentObservations(repairObserver);
      return {
        response: repairedResponse,
        precedent: repairPrecedent,
      };
    } catch {
      return { response, precedent };
    }
  }

  async function recordFailedPrecedentTurn(
    precedent: PreparedPrecedentTurn | null,
    task: string,
    response: string
  ): Promise<void> {
    if (!deps.precedentBridge || !precedent) {
      return;
    }

    await deps.precedentBridge.afterTurn({
      cwd: precedent.cwd,
      threadId: precedent.threadId,
      task,
      response,
      success: false,
      attributedPrecedents: precedent.attributedPrecedents,
    });
    await recordRepairReceipt(precedent);
  }

  async function recordRepairReceipt(precedent: PreparedPrecedentTurn): Promise<void> {
    if (!deps.precedentBridge || !precedent.repair) {
      return;
    }

    await deps.precedentBridge.afterRetry({
      cwd: precedent.cwd,
      threadId: precedent.threadId,
      repairId: precedent.repair.repairId,
      attributedPrecedents: precedent.attributedPrecedents,
    });
  }

  async function preparePrecedentTurn(threadId: string, text: string): Promise<PreparedPrecedentTurn> {
    const options = deps.getConversationOptions();
    if (!deps.precedentBridge) {
      return {
        cwd: options.cwd,
        threadId,
        text,
        attributedPrecedents: [],
        repair: null,
      };
    }

    const beforeTurn = await deps.precedentBridge.beforeTurn({
      cwd: options.cwd,
      threadId,
      task: text,
    });
    const beforeRetry = await deps.precedentBridge.beforeRetry({
      cwd: options.cwd,
      threadId,
      task: text,
      attributedPrecedents: beforeTurn.attributedPrecedents,
    });
    const repair = beforeRetry.repairBlock && beforeRetry.repairId
      ? {
          repairBlock: beforeRetry.repairBlock,
          repairId: beforeRetry.repairId,
        }
      : null;

    return {
      cwd: options.cwd,
      threadId,
      text: repair ? `${repair.repairBlock}\n\n${beforeTurn.task}` : beforeTurn.task,
      attributedPrecedents: beforeTurn.attributedPrecedents,
      repair,
    };
  }

  async function replyFromTimedTurn(
    turn: TimedTurnLike,
    finalOutputRelay: FinalOutputRelay,
    prepareResponse: (response: string) => Promise<string>
  ): Promise<void> {
    if (turn.status === "completed") {
      await finalOutputRelay.send(await prepareResponse(turn.response));
      return;
    }

    finalOutputRelay.queue(turn.completion.then(async (completion) => {
      return {
        response: await prepareResponse(completion.response),
      };
    }));
  }

  async function responseFromTimedTurn(turn: TimedTurnLike): Promise<string> {
    if (turn.status === "completed") {
      return turn.response;
    }
    return (await turn.completion).response;
  }

  async function recoverFromUnavailableThread(
    chatId: string,
    text: string,
    runtimeOptions: PromptTurnRuntimeOptions,
    finalOutputRelay: FinalOutputRelay
  ): Promise<void> {
    const options = deps.getConversationOptions();
    const initialized = await createAndSendFirstMessageWithTimeoutContinuation(options, text, runtimeOptions);
    await deps.bindChatToThread(chatId, initialized.threadId);

    if (initialized.status === "completed") {
      await finalOutputRelay.send(initialized.response);
      return;
    }

    finalOutputRelay.queue(initialized.completion);
  }

  return {
    runPromptThroughCodex
  };
}

function isNoRolloutFoundError(error: unknown): boolean {
  if (!(error instanceof Error)) {
    return false;
  }
  return error.message.includes("no rollout found for thread id");
}

type FinalOutputRelay = {
  send: (response: string) => Promise<void>;
  queue: (completion: Promise<{ response: string }>) => void;
};

type PreparedPrecedentTurn = {
  cwd: string;
  threadId: string;
  text: string;
  attributedPrecedents: string[];
  repair: PreparedPrecedentRepair | null;
};

type PreparedPrecedentRepair = {
  repairBlock: string;
  repairId: string;
};

type PrecedentTurnObserver = {
  observations: Array<Promise<void>>;
};

function createPrecedentTurnObserver(): PrecedentTurnObserver {
  return {
    observations: [],
  };
}

async function settlePrecedentObservations(observer: PrecedentTurnObserver | null): Promise<void> {
  if (!observer || observer.observations.length === 0) {
    return;
  }

  await Promise.allSettled(observer.observations);
}

const EMPTY_CODEX_RESPONSE = "(Empty Codex response)";

function createFinalOutputRelay(sender: (text: string) => Promise<unknown>): FinalOutputRelay {
  let sendQueue = Promise.resolve();

  const queueMessage = (text: string): Promise<void> => {
    const payload = text.trim();
    if (!payload) {
      return sendQueue;
    }

    sendQueue = sendQueue
      .then(async () => {
        await sendTextChunks(sender, payload);
      })
      .catch(() => undefined);
    return sendQueue;
  };

  const send = async (response: string): Promise<void> => {
    const output = response?.trim() ? response : EMPTY_CODEX_RESPONSE;
    await queueMessage(output);
  };

  const queue = (completion: Promise<{ response: string }>): void => {
    void completion
      .then(async ({ response }) => {
        await send(response);
      })
      .catch(async (error) => {
        const message = error instanceof Error ? error.message : String(error);
        await queueMessage(`Codex error: ${message}`);
      })
      .catch(() => undefined);
  };

  return {
    send,
    queue
  };
}
