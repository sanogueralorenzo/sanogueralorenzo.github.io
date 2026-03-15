import {
  createFinalizableDraftStreamControlsForState,
  FinalizableDraftStreamState
} from "./draft-stream-controls.js";
import {
  DraftBreakPreference,
  resolveTelegramDraftStreamingChunking
} from "./draft-chunking.js";

const TELEGRAM_DRAFT_ID_MAX = 2_147_483_647;
const DEFAULT_THROTTLE_MS = 1000;
const MIN_STABLE_BOUNDARY_OFFSET = 64;
const MIN_PROGRESS_DELTA = 48;
const CODE_FENCE = "```";
const INVISIBLE_DRAFT_CLEAR_TEXT = "\u2060";

type TelegramSendMessageDraft = (
  chatId: number,
  draftId: number,
  text: string,
  params?: {
    message_thread_id?: number;
  }
) => Promise<unknown>;

type DraftPreviewMode = "draft";

type TelegramDraftStreamState = {
  nextDraftId: number;
};

const TELEGRAM_DRAFT_STREAM_STATE_KEY = "__codex_remote_telegram_draft_stream_state__";

function resolveDraftStreamState(): TelegramDraftStreamState {
  const globals = globalThis as typeof globalThis & {
    [TELEGRAM_DRAFT_STREAM_STATE_KEY]?: TelegramDraftStreamState;
  };
  if (!globals[TELEGRAM_DRAFT_STREAM_STATE_KEY]) {
    globals[TELEGRAM_DRAFT_STREAM_STATE_KEY] = { nextDraftId: 0 };
  }
  return globals[TELEGRAM_DRAFT_STREAM_STATE_KEY];
}

function allocateTelegramDraftId(): number {
  const state = resolveDraftStreamState();
  state.nextDraftId =
    state.nextDraftId >= TELEGRAM_DRAFT_ID_MAX ? 1 : state.nextDraftId + 1;
  return state.nextDraftId;
}

export type TelegramDraftStream = {
  update: (text: string) => void;
  flush: () => Promise<void>;
  messageId: () => number | undefined;
  previewMode: () => DraftPreviewMode;
  previewRevision: () => number;
  lastDeliveredText: () => string;
  clear: () => Promise<void>;
  stop: () => Promise<void>;
  materialize: () => Promise<number | undefined>;
  forceNewMessage: () => void;
  sendMayHaveLanded: () => boolean;
  cancel: () => Promise<void>;
};

export function createTelegramDraftStream(params: {
  sendMessageDraft: TelegramSendMessageDraft;
  chatId: number;
  messageThreadId?: number;
  throttleMs?: number;
  maxChars?: number;
  minInitialChars?: number;
  breakPreference?: DraftBreakPreference;
  warn?: (message: string) => void;
}): TelegramDraftStream {
  const chunking = resolveTelegramDraftStreamingChunking();
  const maxChars = Math.max(1, Math.min(params.maxChars ?? chunking.maxChars, 4096));
  const minInitialChars = Math.max(1, params.minInitialChars ?? chunking.minChars);
  const breakPreference = params.breakPreference ?? chunking.breakPreference;
  const throttleMs = Math.max(250, params.throttleMs ?? DEFAULT_THROTTLE_MS);
  const threadParams =
    typeof params.messageThreadId === "number"
      ? { message_thread_id: params.messageThreadId }
      : undefined;

  const streamState: FinalizableDraftStreamState = {
    stopped: false,
    final: false
  };

  let draftId = allocateTelegramDraftId();
  let lastSentText = "";
  let lastDeliveredText = "";
  let previewRevision = 0;

  const clearDraftText = async (): Promise<void> => {
    try {
      await params.sendMessageDraft(params.chatId, draftId, "", threadParams);
      lastSentText = "";
      lastDeliveredText = "";
    } catch {
      await params.sendMessageDraft(
        params.chatId,
        draftId,
        INVISIBLE_DRAFT_CLEAR_TEXT,
        threadParams
      );
      lastSentText = INVISIBLE_DRAFT_CLEAR_TEXT;
      lastDeliveredText = "";
    }
  };

  const sendOrEditStreamMessage = async (text: string): Promise<boolean> => {
    if (streamState.stopped && !streamState.final) {
      return false;
    }

    const stabilized = stabilizeSnapshot(text, {
      breakPreference,
      maxChars,
      minStableBoundaryOffset: MIN_STABLE_BOUNDARY_OFFSET,
      isInitialSnapshot: lastDeliveredText.length === 0,
      minInitialChars,
      isFinalSnapshot: streamState.final
    });
    if (!stabilized) {
      return false;
    }

    if (stabilized === lastSentText) {
      return true;
    }

    if (isMinorIncrement(stabilized, lastSentText)) {
      return true;
    }

    try {
      await params.sendMessageDraft(params.chatId, draftId, stabilized, threadParams);
      lastSentText = stabilized;
      lastDeliveredText = stabilized;
      previewRevision += 1;
      return true;
    } catch (error) {
      streamState.stopped = true;
      params.warn?.(
        `telegram stream preview failed: ${error instanceof Error ? error.message : String(error)}`
      );
      return false;
    }
  };

  const controls = createFinalizableDraftStreamControlsForState({
    throttleMs,
    state: streamState,
    sendOrEditStreamMessage
  });

  const forceNewMessage = () => {
    streamState.final = false;
    streamState.stopped = false;
    draftId = allocateTelegramDraftId();
    lastSentText = "";
    lastDeliveredText = "";
    controls.loop.resetPending();
    controls.loop.resetThrottleWindow();
  };

  const cancel = async (): Promise<void> => {
    await controls.stopForClear();
  };

  return {
    update: controls.update,
    flush: controls.loop.flush,
    messageId: () => undefined,
    previewMode: () => "draft",
    previewRevision: () => previewRevision,
    lastDeliveredText: () => lastDeliveredText,
    clear: async () => {
      await controls.stopForClear();
      await clearDraftText();
    },
    stop: controls.stop,
    materialize: async () => undefined,
    forceNewMessage,
    sendMayHaveLanded: () => false,
    cancel
  };
}

function stabilizeSnapshot(
  text: string,
  options: {
    breakPreference: DraftBreakPreference;
    maxChars: number;
    minStableBoundaryOffset: number;
    isInitialSnapshot: boolean;
    minInitialChars: number;
    isFinalSnapshot: boolean;
  }
): string {
  const normalized = text.replaceAll("\r\n", "\n");
  if (!normalized) {
    return "";
  }

  const withoutUnclosedFence = removeUnclosedCodeFence(normalized);
  const stableBoundary = findStableBoundary(withoutUnclosedFence, options.breakPreference);
  if (stableBoundary < options.minStableBoundaryOffset) {
    return "";
  }

  const clipped = withoutUnclosedFence.slice(0, stableBoundary).trimEnd();
  if (!clipped) {
    return "";
  }

  const withLimit =
    clipped.length > options.maxChars
      ? clipped.slice(0, options.maxChars).trimEnd()
      : clipped;
  if (!withLimit) {
    return "";
  }

  if (
    !options.isFinalSnapshot &&
    options.isInitialSnapshot &&
    withLimit.length < options.minInitialChars
  ) {
    return "";
  }

  return withLimit;
}

function findStableBoundary(text: string, breakPreference: DraftBreakPreference): number {
  const paragraphBreak = text.lastIndexOf("\n\n");
  const newlineBreak = text.lastIndexOf("\n");
  const sentenceBreak = findLastSentenceBoundary(text);

  if (breakPreference === "paragraph") {
    if (paragraphBreak >= 0) {
      return paragraphBreak + 2;
    }
    if (newlineBreak >= 0) {
      return newlineBreak + 1;
    }
    if (sentenceBreak >= 0) {
      return sentenceBreak + 1;
    }
  } else if (breakPreference === "newline") {
    if (newlineBreak >= 0) {
      return newlineBreak + 1;
    }
    if (sentenceBreak >= 0) {
      return sentenceBreak + 1;
    }
  } else if (sentenceBreak >= 0) {
    return sentenceBreak + 1;
  } else if (newlineBreak >= 0) {
    return newlineBreak + 1;
  }

  const wordBreak = text.lastIndexOf(" ");
  if (wordBreak >= 0) {
    return wordBreak + 1;
  }

  return -1;
}

function findLastSentenceBoundary(text: string): number {
  for (let index = text.length - 1; index >= 0; index -= 1) {
    const char = text[index];
    if (char === "." || char === "!" || char === "?" || char === ";") {
      return index;
    }
  }
  return -1;
}

function removeUnclosedCodeFence(text: string): string {
  const fenceCount = countOccurrences(text, CODE_FENCE);
  if (fenceCount % 2 === 0) {
    return text;
  }

  const lastFenceIndex = text.lastIndexOf(CODE_FENCE);
  if (lastFenceIndex <= 0) {
    return text;
  }

  return text.slice(0, lastFenceIndex).trimEnd();
}

function countOccurrences(text: string, needle: string): number {
  if (!needle) {
    return 0;
  }

  let count = 0;
  let startIndex = 0;
  while (startIndex <= text.length - needle.length) {
    const index = text.indexOf(needle, startIndex);
    if (index < 0) {
      break;
    }
    count += 1;
    startIndex = index + needle.length;
  }
  return count;
}

function isMinorIncrement(nextSnapshot: string, previousSnapshot: string): boolean {
  if (!previousSnapshot) {
    return false;
  }
  if (!nextSnapshot.startsWith(previousSnapshot)) {
    return false;
  }
  return nextSnapshot.length - previousSnapshot.length < MIN_PROGRESS_DELTA;
}
