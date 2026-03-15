type DraftStreamerOptions = {
  enabled: boolean;
  throttleMs: number;
  maxLength?: number;
  sendDraft: (text: string) => Promise<unknown>;
};

export type TelegramDraftStreamer = {
  pushSnapshot: (text: string) => void;
  stop: (flushPending: boolean) => Promise<void>;
  lastDeliveredDraft: () => string | null;
};

const DEFAULT_MAX_DRAFT_LENGTH = 4096;
const OVERFLOW_PREFIX = "...";
const MIN_STABLE_BOUNDARY_OFFSET = 64;

export function createTelegramDraftStreamer(options: DraftStreamerOptions): TelegramDraftStreamer {
  if (!options.enabled) {
    return {
      pushSnapshot: () => undefined,
      stop: async () => undefined,
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

      const normalized = normalizeSnapshot(stabilizeSnapshot(text), maxLength);
      if (!normalized || normalized === pendingSnapshot || normalized === lastSentSnapshot) {
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
    lastDeliveredDraft: (): string | null => lastSentSnapshot
  };
}

function normalizeSnapshot(text: string, maxLength: number): string {
  if (text.length <= maxLength) {
    return text;
  }

  const keepLength = Math.max(1, maxLength - OVERFLOW_PREFIX.length);
  return `${OVERFLOW_PREFIX}${text.slice(-keepLength)}`;
}

function stabilizeSnapshot(text: string): string {
  const normalized = text.replaceAll("\r\n", "\n");
  if (!normalized) {
    return normalized;
  }

  const completeLineIndex = normalized.lastIndexOf("\n");
  if (completeLineIndex >= MIN_STABLE_BOUNDARY_OFFSET) {
    return normalized.slice(0, completeLineIndex);
  }

  const sentenceEndIndex = findLastSentenceBoundary(normalized);
  if (sentenceEndIndex >= MIN_STABLE_BOUNDARY_OFFSET) {
    return normalized.slice(0, sentenceEndIndex + 1);
  }

  return normalized;
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
