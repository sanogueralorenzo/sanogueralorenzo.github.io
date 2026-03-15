import { vi } from "vitest";

export type TestDraftStream = {
  update: ReturnType<typeof vi.fn<(text: string) => void>>;
  flush: ReturnType<typeof vi.fn<() => Promise<void>>>;
  messageId: ReturnType<typeof vi.fn<() => number | undefined>>;
  previewMode: ReturnType<typeof vi.fn<() => "draft">>;
  previewRevision: ReturnType<typeof vi.fn<() => number>>;
  lastDeliveredText: ReturnType<typeof vi.fn<() => string>>;
  clear: ReturnType<typeof vi.fn<() => Promise<void>>>;
  stop: ReturnType<typeof vi.fn<() => Promise<void>>>;
  materialize: ReturnType<typeof vi.fn<() => Promise<number | undefined>>>;
  forceNewMessage: ReturnType<typeof vi.fn<() => void>>;
  sendMayHaveLanded: ReturnType<typeof vi.fn<() => boolean>>;
  cancel: ReturnType<typeof vi.fn<() => Promise<void>>>;
};

export function createTestDraftStream(): TestDraftStream {
  let previewRevision = 0;
  let lastDeliveredText = "";
  return {
    update: vi.fn().mockImplementation((text: string) => {
      previewRevision += 1;
      lastDeliveredText = text.trimEnd();
    }),
    flush: vi.fn().mockResolvedValue(undefined),
    messageId: vi.fn().mockReturnValue(undefined),
    previewMode: vi.fn().mockReturnValue("draft"),
    previewRevision: vi.fn().mockImplementation(() => previewRevision),
    lastDeliveredText: vi.fn().mockImplementation(() => lastDeliveredText),
    clear: vi.fn().mockResolvedValue(undefined),
    stop: vi.fn().mockResolvedValue(undefined),
    materialize: vi.fn().mockResolvedValue(undefined),
    forceNewMessage: vi.fn(),
    sendMayHaveLanded: vi.fn().mockReturnValue(false),
    cancel: vi.fn().mockResolvedValue(undefined)
  };
}

