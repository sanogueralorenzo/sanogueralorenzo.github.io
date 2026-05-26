import { InputFile } from "grammy";
import type {
  ApprovalDecision,
  ApprovalPolicy,
  ApprovalRequest,
  SandboxMode,
  TurnCompletion,
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

const REMOTE_FINAL_INSTRUCTION = "Be concise. Include outcome, validation, and blockers only when relevant. No extended explanation unless asked.";

type ConversationOptions = {
  cwd: string;
  model?: string;
  approvalPolicy?: ApprovalPolicy;
  sandboxMode?: SandboxMode;
  networkAccessEnabled?: boolean | null;
  skipGitRepoCheck?: boolean | null;
};

type TimedTurnLike =
  | { status: "completed"; response: string; imagePaths?: string[] }
  | { status: "timed_out"; completion: Promise<TurnCompletion> };

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
  const threadTurnLocks = new Map<string, Promise<unknown>>();

  async function runPromptThroughCodex(ctx: PromptContext, chatId: string, text: string): Promise<void> {
    const threadId = await deps.store.get(chatId);
    const finalOutputRelay = createFinalOutputRelay(
      (message) => ctx.api.sendMessage(ctx.chat.id, message),
      (path) => ctx.api.sendPhoto(ctx.chat.id, new InputFile(path))
    );
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
      await replyFromTimedTurn(turn, finalOutputRelay, async (completion) => {
        let finalCompletion = completion;
        let finalPrecedent = precedent;
        if (precedentBridge && precedent) {
          const repaired = await repairCurrentTurn(completion, text, precedent, observer, runtimeOptionsFor);
          finalCompletion = repaired.completion;
          finalPrecedent = repaired.precedent;
          await precedentBridge.afterTurn({
            cwd: finalPrecedent.cwd,
            threadId: finalPrecedent.threadId,
            task: text,
            response: finalCompletion.response,
            success: true,
            attributedPrecedents: finalPrecedent.attributedPrecedents,
          });
          await recordRepairReceipt(finalPrecedent);
        }
        return finalCompletion;
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
          const initialized = await createAndSendFirstMessageWithTimeoutContinuation(
            options,
            withRemoteFinalInstruction(text),
            runtimeOptions
          );
          await deps.bindChatToThread(chatId, initialized.threadId);
          deps.pendingNewSessionChats.delete(chatId);
          deps.clearPendingNewSessionCwd(chatId);
          await finalizeTurn(initialized, null, null);
          return;
        }

        await deps.onThreadNotBound(ctx, chatId);
        return;
      }

      await withThreadTurnLock(threadId, async () => {
        const precedent = await preparePrecedentTurn(threadId, text);
        failurePrecedent = precedent;
        const observer = createPrecedentTurnObserver();
        try {
          const turn = await sendMessageWithTimeoutContinuation(
            threadId,
            withRemoteFinalInstruction(precedent.text),
            runtimeOptionsFor(precedent, observer)
          );
          await finalizeTurn(turn, precedent, observer);
          failurePrecedent = null;
          return;
        } catch (error) {
          if (!isNoRolloutFoundError(error)) {
            throw error;
          }
        }

        try {
          const firstTurn = await sendMessageWithoutResumeWithTimeoutContinuation(
            threadId,
            withRemoteFinalInstruction(precedent.text),
            runtimeOptionsFor(precedent, observer)
          );
          await finalizeTurn(firstTurn, precedent, observer);
          failurePrecedent = null;
          return;
        } catch {
          failurePrecedent = null;
          await recoverFromUnavailableThread(chatId, text, runtimeOptions, finalOutputRelay);
          return;
        }
      });
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      await recordFailedPrecedentTurn(failurePrecedent, text, message);
      await ctx.reply(formatFailure("Codex error.", message));
    }
  }

  async function withThreadTurnLock<T>(threadId: string, work: () => Promise<T>): Promise<T> {
    const previous = threadTurnLocks.get(threadId) ?? Promise.resolve();
    const current = previous.then(async () => work());
    const safeCurrent = current.catch(() => undefined);
    threadTurnLocks.set(threadId, safeCurrent);

    try {
      return await current;
    } finally {
      if (threadTurnLocks.get(threadId) === safeCurrent) {
        threadTurnLocks.delete(threadId);
      }
    }
  }

  async function repairCurrentTurn(
    completion: TurnCompletion,
    task: string,
    precedent: PreparedPrecedentTurn,
    observer: PrecedentTurnObserver | null,
    runtimeOptionsForTurn: (
      precedent: PreparedPrecedentTurn | null,
      observer: PrecedentTurnObserver | null
    ) => PromptTurnRuntimeOptions
  ): Promise<{ completion: TurnCompletion; precedent: PreparedPrecedentTurn }> {
    if (!deps.precedentBridge || precedent.repair) {
      return { completion, precedent };
    }

    await settlePrecedentObservations(observer);
    const beforeRetry = await deps.precedentBridge.beforeRetry({
      cwd: precedent.cwd,
      threadId: precedent.threadId,
      task,
      attributedPrecedents: precedent.attributedPrecedents,
    });
    if (!beforeRetry.repairBlock || !beforeRetry.repairId) {
      return { completion, precedent };
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
        withRemoteFinalInstruction(beforeRetry.repairBlock),
        runtimeOptionsForTurn(repairPrecedent, repairObserver)
      );
      const repairedCompletion = await completionFromTimedTurn(repairedTurn);
      await settlePrecedentObservations(repairObserver);
      return {
        completion: repairedCompletion,
        precedent: repairPrecedent,
      };
    } catch {
      return { completion, precedent };
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
    prepareCompletion: (completion: TurnCompletion) => Promise<TurnCompletion>
  ): Promise<void> {
    const completion = turn.status === "completed"
      ? completionFromCompletedTurn(turn)
      : await turn.completion;
    await finalOutputRelay.send(await prepareCompletion(completion));
  }

  async function completionFromTimedTurn(turn: TimedTurnLike): Promise<TurnCompletion> {
    if (turn.status === "completed") {
      return completionFromCompletedTurn(turn);
    }
    return turn.completion;
  }

  async function recoverFromUnavailableThread(
    chatId: string,
    text: string,
    runtimeOptions: PromptTurnRuntimeOptions,
    finalOutputRelay: FinalOutputRelay
  ): Promise<void> {
    const options = deps.getConversationOptions();
    const initialized = await createAndSendFirstMessageWithTimeoutContinuation(
      options,
      withRemoteFinalInstruction(text),
      runtimeOptions
    );
    await deps.bindChatToThread(chatId, initialized.threadId);

    if (initialized.status === "completed") {
      await finalOutputRelay.send(completionFromCompletedTurn(initialized));
      return;
    }

    await finalOutputRelay.send(await initialized.completion);
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

function withRemoteFinalInstruction(text: string): string {
  return `${text}\n\n${REMOTE_FINAL_INSTRUCTION}`;
}

type FinalOutputRelay = {
  send: (completion: TurnCompletion) => Promise<void>;
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

function completionFromCompletedTurn(turn: { response: string; imagePaths?: string[] }): TurnCompletion {
  return {
    response: turn.response,
    imagePaths: turn.imagePaths ?? [],
  };
}

function createFinalOutputRelay(
  sender: (text: string) => Promise<unknown>,
  imageSender: (path: string) => Promise<unknown>
): FinalOutputRelay {
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

  const send = async (completion: TurnCompletion): Promise<void> => {
    const output = completion.response?.trim() ? completion.response : EMPTY_CODEX_RESPONSE;
    await queueMessage(output);
    for (const path of completion.imagePaths ?? []) {
      try {
        await imageSender(path);
      } catch {
        await queueMessage(`Image generated but Telegram upload failed:\n${path}`);
      }
    }
  };

  return {
    send
  };
}
