import { createTelegramDraftStream } from "./draft-stream.js";

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

export function createTelegramDraftStreamer(options: DraftStreamerOptions): TelegramDraftStreamer {
  if (!options.enabled) {
    return {
      pushSnapshot: () => undefined,
      stop: async () => undefined,
      clear: async () => undefined,
      lastDeliveredDraft: () => null
    };
  }

  const stream = createTelegramDraftStream({
    sendMessageDraft: async (_chatId, _draftId, text) => options.sendDraft(text),
    chatId: 0,
    throttleMs: options.throttleMs,
    maxChars: options.maxLength
  });

  return {
    pushSnapshot: (text: string): void => {
      stream.update(text);
    },
    stop: async (flushPendingSnapshot: boolean): Promise<void> => {
      if (flushPendingSnapshot) {
        await stream.stop();
        return;
      }
      await stream.cancel();
    },
    clear: stream.clear,
    lastDeliveredDraft: (): string | null => stream.lastDeliveredText() || null
  };
}
