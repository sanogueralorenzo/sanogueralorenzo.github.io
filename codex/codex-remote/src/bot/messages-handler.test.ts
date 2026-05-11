import { Bot } from "grammy";
import { describe, expect, it, vi } from "vitest";
import { registerMessageHandlers } from "./messages-handler.js";

type TextHandler = (ctx: {
  chat: { id: number };
  message: { text: string };
  reply: (text: string, options?: unknown) => Promise<unknown>;
}) => Promise<void>;

function registerHandlers() {
  const textHandlers: TextHandler[] = [];
  const voiceHandlers: Array<(ctx: { chat: { id: number } }) => Promise<void>> = [];
  const bot = {
    on: vi.fn((event: string, handler: unknown) => {
      if (event === "message:text") {
        textHandlers.push(handler as TextHandler);
      }
      if (event === "message:voice") {
        voiceHandlers.push(handler as (ctx: { chat: { id: number } }) => Promise<void>);
      }
    }),
  } as unknown as Bot;

  const handlers = {
    onStart: vi.fn(),
    onHelp: vi.fn(),
    onAction: vi.fn(),
    onTryResumeText: vi.fn(async () => false),
    onTryNewFolderText: vi.fn(async () => false),
    onTryApprovalText: vi.fn(async () => false),
    onPrompt: vi.fn(),
    onVoice: vi.fn(),
  };

  registerMessageHandlers(bot, handlers);

  return {
    handlers,
    sendText: async (text: string) => {
      await textHandlers[0]({
        chat: { id: 123 },
        message: { text },
        reply: vi.fn(),
      });
    },
  };
}

describe("registerMessageHandlers", () => {
  it("passes unknown slash commands through as prompts", async () => {
    const { handlers, sendText } = registerHandlers();

    await sendText("/goal ship the Telegram bridge");

    expect(handlers.onPrompt).toHaveBeenCalledWith(expect.anything(), "123", "/goal ship the Telegram bridge");
  });

  it("still handles known text actions before prompts", async () => {
    const { handlers, sendText } = registerHandlers();

    await sendText("new");

    expect(handlers.onAction).toHaveBeenCalledWith("123", "new", expect.any(Function));
    expect(handlers.onPrompt).not.toHaveBeenCalled();
  });
});
