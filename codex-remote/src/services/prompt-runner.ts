import {
  ApprovalDecision,
  ApprovalPolicy,
  ApprovalRequest,
  SandboxMode,
  TurnProgressEvent,
  createAndSendFirstMessageWithTimeoutContinuation,
  sendMessageWithoutResumeWithTimeoutContinuation,
  sendMessageWithTimeoutContinuation
} from "../adapters/app-server-client.js";
import { BindingStore } from "../adapters/binding-store.js";
import { formatFailure } from "../bot/messages.js";
import { PromptContext } from "../bot/context.js";

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

type PromptRunnerDeps = {
  store: BindingStore;
  pendingNewSessionChats: Set<string>;
  getPendingNewSessionCwd: (chatId: string) => string | null;
  clearPendingNewSessionCwd: (chatId: string) => void;
  onThreadNotBound: (ctx: PromptContext, chatId: string) => Promise<void>;
  getConversationOptions: () => ConversationOptions;
  bindChatToThread: (chatId: string, threadId: string) => Promise<void>;
  resolveThreadTitle: (threadId: string) => Promise<string>;
  requestApprovalFromTelegram: (ctx: PromptContext, chatId: string, request: ApprovalRequest) => Promise<ApprovalDecision>;
};

const TELEGRAM_MESSAGE_LIMIT = 4096;
const TELEGRAM_MESSAGE_CHUNK = 3900;

export function createPromptRunner(deps: PromptRunnerDeps) {
  async function runPromptThroughCodex(ctx: PromptContext, chatId: string, text: string): Promise<void> {
    const progressReporter = createTurnProgressReporter(ctx);
    const threadId = await deps.store.get(chatId);
    const runtimeOptions = {
      approvalHandler: (request: ApprovalRequest) => deps.requestApprovalFromTelegram(ctx, chatId, request),
      onTurnEvent: (event: TurnProgressEvent) => {
        progressReporter.onTurnEvent(event);
      }
    };
    const finalizeTurn = async (turn: TimedTurnLike, delayedIntro = "Delayed:"): Promise<void> => {
      await progressReporter.flush();
      await replyFromTimedTurn(ctx, turn, delayedIntro);
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
          await deps.bindChatToThread(chatId, initialized.conversationId);
          deps.pendingNewSessionChats.delete(chatId);
          deps.clearPendingNewSessionCwd(chatId);
          await finalizeTurn(initialized);
          return;
        }

        await deps.onThreadNotBound(ctx, chatId);
        return;
      }

      try {
        const turn = await sendMessageWithTimeoutContinuation(threadId, text, runtimeOptions);
        await finalizeTurn(turn);
        return;
      } catch (error) {
        if (!isNoRolloutFoundError(error)) {
          throw error;
        }
      }

      try {
        const firstTurn = await sendMessageWithoutResumeWithTimeoutContinuation(threadId, text, runtimeOptions);
        await finalizeTurn(firstTurn);
        return;
      } catch {
        await recoverFromUnavailableThread(ctx, chatId, text, runtimeOptions);
        return;
      }
    } catch (error) {
      await progressReporter.flush();
      const message = error instanceof Error ? error.message : String(error);
      await ctx.reply(formatFailure("Codex error.", message));
    }
  }

  async function replyFromTimedTurn(
    ctx: PromptContext,
    turn: TimedTurnLike,
    delayedIntro = "Delayed:"
  ): Promise<void> {
    if (turn.status === "completed") {
      await replyCompletedOutput(ctx, turn.response);
      return;
    }

    await replyDelayedNotice(ctx);
    queueBackgroundReply((message) => ctx.api.sendMessage(ctx.chat.id, message), turn.completion, delayedIntro);
  }

  async function recoverFromUnavailableThread(
    ctx: PromptContext,
    chatId: string,
    text: string,
    runtimeOptions: {
      approvalHandler: (request: ApprovalRequest) => Promise<ApprovalDecision>;
    }
  ): Promise<void> {
    const options = deps.getConversationOptions();
    const initialized = await createAndSendFirstMessageWithTimeoutContinuation(options, text, runtimeOptions);
    await deps.bindChatToThread(chatId, initialized.conversationId);

    const title = await deps.resolveThreadTitle(initialized.conversationId);
    if (initialized.status === "completed") {
      await replyCompletedOutput(ctx, initialized.response);
      return;
    }

    await replyDelayedNotice(ctx);
    queueBackgroundReply(
      (message) => ctx.api.sendMessage(ctx.chat.id, message),
      initialized.completion,
      `Delayed for "${title}":`
    );
  }

  function queueBackgroundReply(
    sender: (text: string) => Promise<unknown>,
    completion: Promise<{ response: string }>,
    intro: string
  ): void {
    void completion
      .then(async ({ response }) => {
        const output = response?.trim() ? response : "(Empty Codex response)";
        await sendTextChunks(sender, `${intro}\n\n${output}`);
      })
      .catch(async (error) => {
        const message = error instanceof Error ? error.message : String(error);
        await sender(`Codex error: ${message}`);
      })
      .catch(() => undefined);
  }

  return {
    runPromptThroughCodex
  };
}

async function replyCompletedOutput(ctx: PromptContext, response: string): Promise<void> {
  const output = response || "(Empty Codex response)";
  await sendTextChunks((message) => ctx.reply(message), output);
}

async function replyDelayedNotice(ctx: PromptContext): Promise<void> {
  void ctx;
}

type TurnProgressReporter = {
  onTurnEvent: (event: TurnProgressEvent) => void;
  flush: () => Promise<void>;
};

function createTurnProgressReporter(ctx: PromptContext): TurnProgressReporter {
  const startedItems = new Set<string>();
  const completedItems = new Set<string>();
  const throttleState = new Map<string, { sentAtMs: number; text: string }>();
  const postMessage = (text: string) => sendTextChunks((message) => ctx.api.sendMessage(ctx.chat.id, message), text);
  let sendQueue: Promise<void> = Promise.resolve();

  const enqueue = (text: string): void => {
    const normalized = text.trim();
    if (!normalized) {
      return;
    }
    sendQueue = sendQueue
      .then(async () => {
        await postMessage(normalized);
      })
      .catch(() => undefined);
  };

  const enqueueThrottled = (bucket: string, text: string, intervalMs: number): void => {
    const now = Date.now();
    const previous = throttleState.get(bucket);
    if (previous && previous.text === text) {
      return;
    }
    if (previous && now - previous.sentAtMs < intervalMs) {
      return;
    }
    throttleState.set(bucket, { sentAtMs: now, text });
    enqueue(text);
  };

  const onTurnEvent = (event: TurnProgressEvent): void => {
    if (event.kind === "itemStarted") {
      const key = `${event.itemType}:${event.itemId}`;
      if (startedItems.has(key)) {
        return;
      }
      startedItems.add(key);

      if (event.itemType === "reasoning") {
        enqueue("Thinking…");
        return;
      }
      if (event.itemType === "plan") {
        enqueue("Planning…");
        return;
      }
      if (event.itemType === "commandExecution") {
        const command = truncateProgressText(event.command, 240);
        if (command) {
          enqueue(`Running command:\n${command}`);
        } else {
          enqueue("Running command…");
        }
        return;
      }
      return;
    }

    if (event.kind === "itemCompleted") {
      const key = `${event.itemType}:${event.itemId}`;
      if (!completedItems.has(key)) {
        completedItems.add(key);
      } else {
        return;
      }

      if (event.itemType === "commandExecution") {
        const status = event.status ?? "completed";
        const command = truncateProgressText(event.command, 240);
        const output = truncateProgressText(event.output, 500);
        let message = `Command ${status}.`;
        if (command) {
          message += `\n${command}`;
        }
        if (output) {
          message += `\nOutput:\n${output}`;
        }
        enqueue(message);
        return;
      }
      return;
    }

    const snippet = truncateProgressText(event.text, 320);
    if (!snippet) {
      return;
    }

    switch (event.kind) {
      case "reasoningDelta":
        enqueueThrottled("reasoning", `Reasoning:\n${snippet}`, 8000);
        return;
      case "planDelta":
        enqueueThrottled("plan", `Plan update:\n${snippet}`, 8000);
        return;
      case "commandOutputDelta":
        enqueueThrottled("command_output", `Command output:\n${snippet}`, 5000);
        return;
      case "agentDelta":
        enqueueThrottled("agent_draft", `Draft answer:\n${snippet}`, 8000);
        return;
      default:
        return;
    }
  };

  return {
    onTurnEvent,
    flush: async (): Promise<void> => {
      await sendQueue;
    }
  };
}

function truncateProgressText(text: string | null, maxLength: number): string | null {
  if (!text) {
    return null;
  }
  const normalized = text.replace(/\s+/g, " ").trim();
  if (normalized.length === 0) {
    return null;
  }
  if (normalized.length <= maxLength) {
    return normalized;
  }
  return `${normalized.slice(0, Math.max(1, maxLength - 3))}...`;
}

async function sendTextChunks(sender: (text: string) => Promise<unknown>, text: string): Promise<void> {
  const chunks = splitTextForTelegram(text);
  for (const chunk of chunks) {
    await sender(chunk);
  }
}

function splitTextForTelegram(text: string, maxLen = TELEGRAM_MESSAGE_CHUNK): string[] {
  if (text.length <= TELEGRAM_MESSAGE_LIMIT) {
    return [text];
  }

  const chunks: string[] = [];
  let remaining = text;
  while (remaining.length > maxLen) {
    let splitAt = remaining.lastIndexOf("\n", maxLen);
    if (splitAt < Math.floor(maxLen * 0.5)) {
      splitAt = remaining.lastIndexOf(" ", maxLen);
    }
    if (splitAt <= 0) {
      splitAt = maxLen;
    }

    const head = remaining.slice(0, splitAt).trimEnd();
    if (head) {
      chunks.push(head);
    }
    remaining = remaining.slice(splitAt).trimStart();
  }

  if (remaining) {
    chunks.push(remaining);
  }

  return chunks.length ? chunks : [""];
}

function isNoRolloutFoundError(error: unknown): boolean {
  if (!(error instanceof Error)) {
    return false;
  }
  return error.message.includes("no rollout found for thread id");
}
