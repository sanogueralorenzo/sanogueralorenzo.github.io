import { Bot } from "grammy";
import { describe, expect, it, vi } from "vitest";
import { registerCommandHandlers } from "./commands.js";

type CommandHandler = (ctx: {
  chat: { id: number };
  message?: { text: string };
  reply: (text: string, options?: unknown) => Promise<unknown>;
}) => Promise<void>;

function registerHandlers() {
  const commandHandlers = new Map<string, CommandHandler>();
  const bot = {
    command: vi.fn((command: string, handler: unknown) => {
      commandHandlers.set(command, handler as CommandHandler);
    }),
  } as unknown as Bot;

  const handlers = {
    onStart: vi.fn(),
    onHelp: vi.fn(),
    onNew: vi.fn(),
    onResume: vi.fn(),
    onDelete: vi.fn(),
    onGoal: vi.fn(),
  };

  registerCommandHandlers(bot, handlers);

  return {
    handlers,
    sendCommand: async (command: string, text: string) => {
      const handler = commandHandlers.get(command);
      if (!handler) {
        throw new Error(`Command not registered: ${command}`);
      }
      await handler({
        chat: { id: 123 },
        message: { text },
        reply: vi.fn(),
      });
    },
  };
}

describe("registerCommandHandlers", () => {
  it("routes /goal with only the payload text", async () => {
    const { handlers, sendCommand } = registerHandlers();

    await sendCommand("goal", "/goal review the PR");

    expect(handlers.onGoal).toHaveBeenCalledWith("123", "review the PR", expect.any(Function));
  });

  it("supports bot-qualified /goal commands", async () => {
    const { handlers, sendCommand } = registerHandlers();

    await sendCommand("goal", "/goal@codex_remote_bot pause");

    expect(handlers.onGoal).toHaveBeenCalledWith("123", "pause", expect.any(Function));
  });
});
