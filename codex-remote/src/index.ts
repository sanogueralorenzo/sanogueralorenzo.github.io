import { existsSync } from "node:fs";
import { spawn } from "node:child_process";
import { dirname, isAbsolute, resolve } from "node:path";
import { homedir } from "node:os";
import process from "node:process";
import { fileURLToPath } from "node:url";
import { config as loadEnv } from "dotenv";
import { Bot, InputFile } from "grammy";
import {
  ApprovalDecision,
  ApprovalPolicy,
  SandboxMode
} from "./adapters/app-server-client.js";
import { BindingStore } from "./adapters/binding-store.js";
import {
  resolveCodexHomeFromEnv
} from "./adapters/codex-sessions.js";
import { registerBotHandlers } from "./bot/index.js";
import { createApprovalService } from "./bot/approvals.js";
import { PromptContext, ReplyFn, ReplyPhotoFn } from "./bot/context.js";
import { quickActionsKeyboard } from "./bot/keyboards.js";
import { HELP_TEXT, formatFailure } from "./bot/messages.js";
import { withActionErrorBoundary, withChatLock } from "./bot/middleware.js";
import { createPromptRunner } from "./services/prompt-runner.js";
import { ListedFolderChoice, ListedThread, createThreadActions } from "./services/thread-actions.js";
import { createVoiceService } from "./services/voice.js";
import { expandHomePath } from "./shared/path-utils.js";

loadEnv();

const token = mustGetEnv("TELEGRAM_BOT_TOKEN");
const userHome = homedir();
const bindingFile = resolve(process.cwd(), "runtime/bindings.json");
const sourceDir = dirname(fileURLToPath(import.meta.url));
const startImagePath = resolve(sourceDir, "../assets/start-logo.png");
const codexHome = resolveCodexHomeFromEnv(process.env.CODEX_HOME);
const defaultApprovalDecision: ApprovalDecision = "decline";
const enableDraftStreaming = true;
const draftStreamingThrottleMs = 500;
const allowedChatIds = parseAllowedChatIds(process.env.TELEGRAM_ALLOWED_CHAT_IDS);
const adminChatIds = parseAllowedChatIds(process.env.TELEGRAM_ADMIN_CHAT_IDS);
ensureStartImageExists(startImagePath);

const store = new BindingStore(bindingFile);
const bot = new Bot(token);

const pendingNewSessionChats = new Set<string>();
const pendingNewSessionCwds = new Map<string, string>();
const lastListedSessions = new Map<string, ListedThread[]>();
const lastListedSessionModes = new Map<string, "resume" | "delete">();
const lastListedFolderChoices = new Map<string, ListedFolderChoice[]>();

const DEFAULT_THREADS_LIMIT = 25;
const APPROVAL_REQUEST_TIMEOUT_MS = 10 * 60 * 1000;

const threadActions = createThreadActions({
  codexHome,
  defaultThreadsLimit: DEFAULT_THREADS_LIMIT,
  store,
  pendingNewSessionChats,
  pendingNewSessionCwds,
  lastListedSessions,
  lastListedSessionModes,
  lastListedFolderChoices,
  resolveDefaultCwd: () => getConversationOptions().cwd,
  bindChatToThread
});

const approvalService = createApprovalService({
  defaultApprovalDecision,
  timeoutMs: APPROVAL_REQUEST_TIMEOUT_MS
});

const promptRunner = createPromptRunner({
  store,
  pendingNewSessionChats,
  getPendingNewSessionCwd: (chatId) => pendingNewSessionCwds.get(chatId) ?? null,
  clearPendingNewSessionCwd: (chatId) => {
    pendingNewSessionCwds.delete(chatId);
  },
  onThreadNotBound: async (ctx) => {
    await ctx.reply(HELP_TEXT, { reply_markup: quickActionsKeyboard() });
  },
  getConversationOptions,
  bindChatToThread,
  resolveThreadTitle: threadActions.resolveThreadTitle,
  requestApprovalFromTelegram: approvalService.requestApprovalFromTelegram,
  enableDraftStreaming,
  draftStreamingThrottleMs
});

const voiceService = createVoiceService({
  token,
  projectRoot: process.cwd()
});

registerBotHandlers(bot, {
  isChatAllowed: (chatId) => {
    if (!allowedChatIds) {
      return true;
    }
    return allowedChatIds.has(chatId);
  },
  onStart: async (_, reply, replyPhoto) => {
    await sendStartResponse(reply, replyPhoto);
  },
  onHelp: async (_, reply) => {
    await sendHelpResponse(reply);
  },
  onRestart: async (chatId, reply) => {
    await handleRestartRequest(chatId, reply);
  },
  onAction: async (chatId, action, reply) => {
    await withActionErrorBoundary(
      () =>
        withChatLock(chatId, async () => {
          await threadActions.executeAction(chatId, action, reply);
        }),
      (message) => reply(formatFailure("Action failed.", message))
    );
  },
  onTryResumeText: async (chatId, text, reply) => {
    return withChatLock(chatId, async () => threadActions.tryPickThreadByText(chatId, text, reply));
  },
  onTryNewFolderText: async (chatId, text, reply) => {
    return withChatLock(chatId, async () => threadActions.tryPickFolderChoiceByText(chatId, text, reply));
  },
  onTryApprovalText: async (ctx, chatId, text) => {
    return approvalService.resolveApprovalFromText(ctx, chatId, text);
  },
  onPrompt: async (ctx, chatId, text) => {
    await withChatLock(chatId, async () => {
      await ctx.api.sendChatAction(ctx.chat.id, "typing");
      await promptRunner.runPromptThroughCodex(ctx, chatId, text);
    });
  },
  onVoice: async (ctx, chatId) => {
    await withChatLock(chatId, async () => {
      await ctx.api.sendChatAction(ctx.chat.id, "typing");
      try {
        const transcript = await voiceService.transcribeVoiceMessage(ctx as PromptContext);
        await promptRunner.runPromptThroughCodex(ctx as PromptContext, chatId, transcript);
      } catch (error) {
        const message = error instanceof Error ? error.message : String(error);
        await ctx.reply(formatFailure("Voice transcription failed.", message));
      }
    });
  },
});

bot.catch(async (error) => {
  console.error("Telegram bot error:", error.error);
});

console.log(`Telegram Codex bridge is running. Codex home: ${codexHome}.`);
if (allowedChatIds) {
  console.log(`Telegram chat allowlist is active (${allowedChatIds.size} chat id${allowedChatIds.size === 1 ? "" : "s"}).`);
}
if (adminChatIds) {
  console.log(
    `Telegram restart admin allowlist is active (${adminChatIds.size} chat id${adminChatIds.size === 1 ? "" : "s"}).`
  );
} else {
  console.log("Telegram restart command is disabled (TELEGRAM_ADMIN_CHAT_IDS is not set).");
}
try {
  const me = await bot.api.getMe();
  console.log(`Telegram auth OK: @${me.username ?? me.first_name}`);
  await bot.start({
    drop_pending_updates: true,
    onStart: (info) => {
      console.log(`Telegram polling started as @${info.username ?? info.first_name}`);
    }
  });
} catch (error) {
  const message = error instanceof Error ? error.stack ?? error.message : String(error);
  console.error(`Telegram bot failed to start: ${message}`);
  process.exit(1);
}

function mustGetEnv(name: string): string {
  const value = process.env[name];
  if (!value) {
    throw new Error(`Missing required env var: ${name}`);
  }
  return value;
}

function getConversationOptions(): {
  cwd: string;
  model?: string;
  approvalPolicy?: ApprovalPolicy;
  sandboxMode?: SandboxMode;
  networkAccessEnabled?: boolean | null;
  skipGitRepoCheck?: boolean | null;
} {
  const options: {
    cwd: string;
    model?: string;
    approvalPolicy?: ApprovalPolicy;
    sandboxMode?: SandboxMode;
    networkAccessEnabled?: boolean | null;
    skipGitRepoCheck?: boolean | null;
  } = {
    cwd: resolveUserPath(process.env.CODEX_WORKING_DIRECTORY) ?? userHome
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

  options.skipGitRepoCheck = true;

  return options;
}

async function bindChatToThread(chatId: string, threadId: string): Promise<void> {
  await store.set(chatId, threadId);
}

function parseApprovalPolicy(value?: string): ApprovalPolicy | undefined {
  const allowed = new Set(["never", "on-request", "on-failure", "untrusted"]);
  if (!value || !allowed.has(value)) {
    return undefined;
  }
  return value as ApprovalPolicy;
}

function parseSandboxMode(value?: string): SandboxMode | undefined {
  const allowed = new Set(["read-only", "workspace-write", "danger-full-access"]);
  if (!value || !allowed.has(value)) {
    return undefined;
  }
  return value as SandboxMode;
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

function parseAllowedChatIds(value?: string): Set<string> | null {
  if (value === undefined) {
    return null;
  }

  const items = value
    .split(",")
    .map((part) => part.trim())
    .filter((part) => part.length > 0);

  return new Set(items);
}

async function sendHelpResponse(reply: ReplyFn): Promise<void> {
  await reply(HELP_TEXT, { reply_markup: quickActionsKeyboard() });
}

async function handleRestartRequest(chatId: string, reply: ReplyFn): Promise<void> {
  if (!isRestartAdminChat(chatId)) {
    await reply("Restart denied. This command is restricted to admin chats.");
    return;
  }

  const cliPath = resolve(process.cwd(), "scripts/codex-remote");
  if (!existsSync(cliPath)) {
    await reply(`Restart failed. Missing CLI script at ${cliPath}.`);
    return;
  }

  await reply("Restarting Codex Remote...");

  const child = spawn(cliPath, ["restart", "--plain"], {
    detached: true,
    stdio: "ignore",
    cwd: process.cwd()
  });
  child.unref();
}

async function sendStartResponse(reply: ReplyFn, replyPhoto: ReplyPhotoFn): Promise<void> {
  await replyPhoto(new InputFile(startImagePath));
  await sendHelpResponse(reply);
}

function ensureStartImageExists(path: string): void {
  if (!existsSync(path)) {
    throw new Error(`Missing Telegram start image asset at: ${path}`);
  }
}

function resolveUserPath(value?: string): string | null {
  if (!value || !value.trim()) {
    return null;
  }

  const expanded = expandHomePath(value.trim());
  if (isAbsolute(expanded)) {
    return expanded;
  }
  return resolve(process.cwd(), expanded);
}

function isRestartAdminChat(chatId: string): boolean {
  if (!adminChatIds) {
    return false;
  }

  return adminChatIds.has(chatId);
}
