type DraftStreamerOptions = {
  enabled: boolean;
  throttleMs: number;
  maxLength?: number;
  sendDraft: (text: string) => Promise<unknown>;
};

export type TelegramDraftStreamer = {
  pushSnapshot: (text: string) => void;
  stop: (flushPending: boolean) => Promise<void>;
  clear: () => Promise<void>;
  lastDeliveredDraft: () => string | null;
};

const DEFAULT_MAX_DRAFT_LENGTH = 800;
const MIN_STABLE_BOUNDARY_OFFSET = 64;
const MIN_INITIAL_STABLE_CHARS = 200;
const MIN_PROGRESS_DELTA = 48;
const CODE_FENCE = "```";
const INVISIBLE_DRAFT_CLEAR_TEXT = "\u2060";

export function createTelegramDraftStreamer(options: DraftStreamerOptions): TelegramDraftStreamer {
  if (!options.enabled) {
    return {
      pushSnapshot: () => undefined,
      stop: async () => undefined,
      clear: async () => undefined,
      lastDeliveredDraft: () => null
    };
  }

  const maxLength = Math.max(1, options.maxLength ?? DEFAULT_MAX_DRAFT_LENGTH);
  const throttleMs = Math.max(100, options.throttleMs);

  let stopped = false;
  let disabled = false;
  let timer: NodeJS.Timeout | null = null;
  let pendingSnapshot: string | null = null;
  let lastSentSnapshot: string | null = null;
  let hasQueuedInitialSnapshot = false;
  let sendQueue: Promise<void> = Promise.resolve();

  const flushPending = (): void => {
    if (disabled) {
      pendingSnapshot = null;
      return;
    }

    const snapshot = pendingSnapshot;
    pendingSnapshot = null;
    if (!snapshot || snapshot === lastSentSnapshot) {
      return;
    }

    sendQueue = sendQueue
      .then(async () => {
        await options.sendDraft(snapshot);
        lastSentSnapshot = snapshot;
      })
      .catch(() => {
        disabled = true;
      });
  };

  const scheduleFlush = (): void => {
    if (timer || disabled || stopped) {
      return;
    }

    timer = setTimeout(() => {
      timer = null;
      flushPending();
    }, throttleMs);
  };

  return {
    pushSnapshot: (text: string): void => {
      if (stopped || disabled) {
        return;
      }

      const normalized = normalizeSnapshot(
        stabilizeSnapshot(text, !hasQueuedInitialSnapshot),
        maxLength
      );
      if (!normalized || normalized === pendingSnapshot || normalized === lastSentSnapshot) {
        return;
      }

      if (isMinorIncrement(normalized, lastSentSnapshot)) {
        return;
      }

      pendingSnapshot = normalized;
      if (!hasQueuedInitialSnapshot) {
        hasQueuedInitialSnapshot = true;
        flushPending();
        return;
      }
      scheduleFlush();
    },
    stop: async (flushPendingSnapshot: boolean): Promise<void> => {
      stopped = true;
      if (timer) {
        clearTimeout(timer);
        timer = null;
      }

      if (!flushPendingSnapshot) {
        pendingSnapshot = null;
      } else {
        flushPending();
      }

      await sendQueue;
    },
    clear: async (): Promise<void> => {
      sendQueue = sendQueue
        .then(async () => {
          try {
            await options.sendDraft("");
            lastSentSnapshot = "";
          } catch {
            // Fallback for strict 1+ char validators while remaining visually blank.
            await options.sendDraft(INVISIBLE_DRAFT_CLEAR_TEXT);
            lastSentSnapshot = INVISIBLE_DRAFT_CLEAR_TEXT;
          }
        })
        .catch(() => undefined);
      await sendQueue;
    },
    lastDeliveredDraft: (): string | null => lastSentSnapshot
  };
}

function normalizeSnapshot(text: string, maxLength: number): string {
  if (!text) {
    return "";
  }

  if (text.length <= maxLength) {
    return text.trimEnd();
  }

  return text.slice(0, maxLength).trimEnd();
}

function stabilizeSnapshot(text: string, isInitialSnapshot: boolean): string {
  const normalized = text.replaceAll("\r\n", "\n");
  if (!normalized) {
    return "";
  }

  const withoutUnclosedFence = removeUnclosedCodeFence(normalized);
  const stableBoundary = findStableBoundary(withoutUnclosedFence);
  if (stableBoundary < MIN_STABLE_BOUNDARY_OFFSET) {
    return "";
  }

  const clipped =
    stableBoundary >= 0
      ? withoutUnclosedFence.slice(0, stableBoundary)
      : withoutUnclosedFence;
  const stabilized = clipped.trimEnd();
  if (isInitialSnapshot && stabilized.length < MIN_INITIAL_STABLE_CHARS) {
    return "";
  }
  return stabilized;
}

function findStableBoundary(text: string): number {
  const paragraphBreak = text.lastIndexOf("\n\n");
  if (paragraphBreak >= 0) {
    return paragraphBreak + 2;
  }

  const completeLine = text.lastIndexOf("\n");
  if (completeLine >= 0) {
    return completeLine + 1;
  }

  const sentenceEnd = findLastSentenceBoundary(text);
  if (sentenceEnd >= 0) {
    return sentenceEnd + 1;
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

function isMinorIncrement(nextSnapshot: string, previousSnapshot: string | null): boolean {
  if (!previousSnapshot) {
    return false;
  }

  if (!nextSnapshot.startsWith(previousSnapshot)) {
    return false;
  }

  return nextSnapshot.length - previousSnapshot.length < MIN_PROGRESS_DELTA;
}
