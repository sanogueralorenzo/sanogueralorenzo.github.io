import { resolve } from "node:path";
import process from "node:process";
import { config as loadEnv } from "dotenv";
import { Bot } from "grammy";
import { Codex, Thread, ThreadOptions } from "@openai/codex-sdk";
import { BindingStore } from "./binding-store.js";

loadEnv();

const token = mustGetEnv("TELEGRAM_BOT_TOKEN");
const bindingFile = resolve(process.cwd(), process.env.BINDINGS_FILE ?? "data/bindings.json");

const store = new BindingStore(bindingFile);
const bot = new Bot(token);
const codex = new Codex({
  apiKey: process.env.CODEX_API_KEY,
  baseUrl: process.env.OPENAI_BASE_URL
});

const pendingThreads = new Map<string, Thread>();
const threadCache = new Map<string, Thread>();
const chatLocks = new Map<string, Promise<void>>();

const helpText = [
  "Commands:",
  "/new - start a new Codex thread and bind this chat",
  "/bind <thread_id> - bind an existing Codex thread",
  "/thread - show current thread binding",
  "/unbind - remove current binding",
  "",
  "After binding, send normal text messages and they are forwarded to Codex."
].join("\n");

bot.command("start", (ctx) => ctx.reply(helpText));
bot.command("help", (ctx) => ctx.reply(helpText));

bot.command("new", async (ctx) => {
  const chatId = String(ctx.chat.id);
  const thread = codex.startThread(getThreadOptions());

  pendingThreads.set(chatId, thread);
  const existingThreadId = await store.get(chatId);
  if (existingThreadId) {
    threadCache.delete(existingThreadId);
  }
  await store.remove(chatId);

  await ctx.reply("Started a fresh Codex session. Send your next message to initialize and bind it.");
});

bot.command("bind", async (ctx) => {
  const chatId = String(ctx.chat.id);
  const threadId = String(ctx.match ?? "").trim();

  if (!threadId) {
    await ctx.reply("Usage: /bind <thread_id>");
    return;
  }

  const previousThreadId = await store.get(chatId);
  if (previousThreadId) {
    threadCache.delete(previousThreadId);
  }
  pendingThreads.delete(chatId);
  await store.set(chatId, threadId);
  threadCache.set(threadId, codex.resumeThread(threadId, getThreadOptions()));

  await ctx.reply(`Bound this chat to thread: ${threadId}`);
});

bot.command("thread", async (ctx) => {
  const chatId = String(ctx.chat.id);
  const bound = await store.get(chatId);

  if (bound) {
    await ctx.reply(`Current thread: ${bound}`);
    return;
  }

  if (pendingThreads.has(chatId)) {
    await ctx.reply("A new thread is pending initialization. Send a message to start it.");
    return;
  }

  await ctx.reply("No thread is bound. Use /new or /bind <thread_id>.");
});

bot.command("unbind", async (ctx) => {
  const chatId = String(ctx.chat.id);
  pendingThreads.delete(chatId);
  const bound = await store.get(chatId);
  if (bound) {
    threadCache.delete(bound);
  }
  const removed = await store.remove(chatId);

  if (!removed) {
    await ctx.reply("No existing binding for this chat.");
    return;
  }

  await ctx.reply("Binding removed.");
});

bot.on("message:text", async (ctx) => {
  const text = ctx.message.text.trim();
  if (!text || text.startsWith("/")) {
    return;
  }

  const chatId = String(ctx.chat.id);
  await withChatLock(chatId, async () => {
    await ctx.api.sendChatAction(ctx.chat.id, "typing");

    const { thread, boundThreadId } = await getThreadForChat(chatId);
    if (!thread) {
      await ctx.reply("No thread bound. Use /new or /bind <thread_id>.");
      return;
    }

    try {
      const turn = await thread.run(text);
      const response = turn.finalResponse.trim() || "(empty Codex response)";
      await ctx.reply(response);

      if (thread.id) {
        const latestThreadId = thread.id;
        if (boundThreadId !== latestThreadId) {
          await store.set(chatId, latestThreadId);
          threadCache.set(latestThreadId, thread);
          pendingThreads.delete(chatId);
        }
      }
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      await ctx.reply(`Codex error: ${message}`);
    }
  });
});

bot.catch(async (error) => {
  console.error("Telegram bot error:", error.error);
});

console.log("Telegram Codex bridge is running.");
await bot.start();

function mustGetEnv(name: string): string {
  const value = process.env[name];
  if (!value) {
    throw new Error(`Missing required env var: ${name}`);
  }
  return value;
}

function getThreadOptions(): ThreadOptions {
  const options: ThreadOptions = {
    workingDirectory: resolve(process.cwd(), process.env.CODEX_WORKING_DIRECTORY ?? "."),
    skipGitRepoCheck: parseBoolean(process.env.CODEX_SKIP_GIT_REPO_CHECK) ?? true
  };

  const model = process.env.CODEX_MODEL;
  if (model) {
    options.model = model;
  }

  const approvalPolicy = parseApprovalPolicy(process.env.CODEX_APPROVAL_POLICY);
  if (approvalPolicy) {
    options.approvalPolicy = approvalPolicy;
  }

  const sandboxMode = parseSandboxMode(process.env.CODEX_SANDBOX_MODE);
  if (sandboxMode) {
    options.sandboxMode = sandboxMode;
  }

  const networkAccess = parseBoolean(process.env.CODEX_NETWORK_ACCESS_ENABLED);
  if (networkAccess !== null) {
    options.networkAccessEnabled = networkAccess;
  }

  return options;
}

async function getThreadForChat(chatId: string): Promise<{ thread: Thread | null; boundThreadId: string | null }> {
  const pending = pendingThreads.get(chatId);
  if (pending) {
    return { thread: pending, boundThreadId: null };
  }

  const threadId = await store.get(chatId);
  if (!threadId) {
    return { thread: null, boundThreadId: null };
  }

  const cached = threadCache.get(threadId);
  if (cached) {
    return { thread: cached, boundThreadId: threadId };
  }

  const thread = codex.resumeThread(threadId, getThreadOptions());
  threadCache.set(threadId, thread);
  return { thread, boundThreadId: threadId };
}

function parseApprovalPolicy(value?: string): ThreadOptions["approvalPolicy"] | undefined {
  const allowed = new Set(["never", "on-request", "on-failure", "untrusted"]);
  if (!value || !allowed.has(value)) {
    return undefined;
  }
  return value as ThreadOptions["approvalPolicy"];
}

function parseSandboxMode(value?: string): ThreadOptions["sandboxMode"] | undefined {
  const allowed = new Set(["read-only", "workspace-write", "danger-full-access"]);
  if (!value || !allowed.has(value)) {
    return undefined;
  }
  return value as ThreadOptions["sandboxMode"];
}

function parseBoolean(value?: string): boolean | null {
  if (!value) {
    return null;
  }
  if (value === "true") {
    return true;
  }
  if (value === "false") {
    return false;
  }
  return null;
}

async function withChatLock(chatId: string, work: () => Promise<void>): Promise<void> {
  const previous = chatLocks.get(chatId) ?? Promise.resolve();
  const current = previous.then(async () => {
    await work();
  });
  const safeCurrent = current.catch(() => undefined);
  chatLocks.set(chatId, safeCurrent);

  try {
    await current;
  } finally {
    if (chatLocks.get(chatId) === safeCurrent) {
      chatLocks.delete(chatId);
    }
  }
}
