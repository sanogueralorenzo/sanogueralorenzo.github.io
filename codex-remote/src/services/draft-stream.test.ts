import { describe, expect, it, vi } from "vitest";
import { createTelegramDraftStream } from "./draft-stream.js";

function createDraftApi() {
  return {
    sendMessageDraft: vi.fn().mockResolvedValue(true)
  };
}

describe("createTelegramDraftStream", () => {
  it("uses draft preview mode", () => {
    const api = createDraftApi();
    const stream = createTelegramDraftStream({
      sendMessageDraft: api.sendMessageDraft,
      chatId: 123
    });

    expect(stream.previewMode()).toBe("draft");
    expect(stream.messageId()).toBeUndefined();
  });

  it("waits for initial stable chunk before first draft send", async () => {
    const api = createDraftApi();
    const stream = createTelegramDraftStream({
      sendMessageDraft: api.sendMessageDraft,
      chatId: 123
    });

    stream.update("short");
    await stream.flush();

    expect(api.sendMessageDraft).not.toHaveBeenCalled();
  });

  it("sends stabilized draft once enough content is available", async () => {
    const api = createDraftApi();
    const stream = createTelegramDraftStream({
      sendMessageDraft: api.sendMessageDraft,
      chatId: 123,
      minInitialChars: 50
    });

    stream.update(
      "This is a sufficiently long initial paragraph for streaming behavior.\n\nAdditional context."
    );
    await stream.flush();

    expect(api.sendMessageDraft).toHaveBeenCalledTimes(1);
    const sentText = api.sendMessageDraft.mock.calls[0]?.[2];
    expect(typeof sentText).toBe("string");
    expect(sentText.length).toBeGreaterThanOrEqual(50);
    expect(stream.previewRevision()).toBe(1);
  });

  it("clears draft after stop/clear", async () => {
    const api = createDraftApi();
    const stream = createTelegramDraftStream({
      sendMessageDraft: api.sendMessageDraft,
      chatId: 123,
      minInitialChars: 10
    });

    stream.update("This is long enough to be emitted.\n");
    await stream.stop();
    await stream.clear();

    const calls = api.sendMessageDraft.mock.calls;
    const clearCall = calls.find((call) => call[2] === "" || call[2] === "\u2060");
    expect(clearCall).toBeDefined();
  });

  it("rotates draft id when forceNewMessage is called", async () => {
    const api = createDraftApi();
    const stream = createTelegramDraftStream({
      sendMessageDraft: api.sendMessageDraft,
      chatId: 123,
      minInitialChars: 10
    });

    stream.update(
      "First emitted chunk with enough content and a stable boundary for preview output.\n\nA"
    );
    await stream.flush();
    stream.forceNewMessage();
    stream.update(
      "Second emitted chunk with enough content and a stable boundary for preview output.\n\nB"
    );
    await stream.flush();

    expect(api.sendMessageDraft).toHaveBeenCalledTimes(2);
    const firstDraftId = api.sendMessageDraft.mock.calls[0]?.[1];
    const secondDraftId = api.sendMessageDraft.mock.calls[1]?.[1];
    expect(firstDraftId).not.toBe(secondDraftId);
  });
});
