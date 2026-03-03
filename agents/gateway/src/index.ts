import { isAbsolute, resolve } from "node:path";
import { homedir } from "node:os";
import process from "node:process";
import { config as loadEnv } from "dotenv";
import { Bot } from "grammy";
import {
  ApprovalDecision,
  ApprovalPolicy,
  SandboxMode
} from "./adapters/app-server-client.js";
import { BindingStore } from "./adapters/binding-store.js";
import { forceSessionSource, resolveCodexHomeFromEnv } from "./adapters/codex-sessions.js";
import { registerBotHandlers } from "./bot/index.js";
import { createApprovalService } from "./bot/approvals.js";
import { PromptContext } from "./bot/context.js";
import { quickActionsKeyboard } from "./bot/keyboards.js";
import { HELP_TEXT, formatFailure } from "./bot/messages.js";
import { withActionErrorBoundary, withChatLock } from "./bot/middleware.js";
import { createPromptRunner } from "./services/prompt-runner.js";
import { ListedFolderChoice, ListedThread, createThreadActions } from "./services/thread-actions.js";
import { createVoiceService, limitTelegramText } from "./services/voice.js";
import { expandHomePath } from "./shared/path-utils.js";

loadEnv();

const token = mustGetEnv("TELEGRAM_BOT_TOKEN");
const userHome = homedir();
const bindingFile = resolve(process.cwd(), "runtime/bindings.json");
const codexHome = resolveCodexHomeFromEnv(process.env.CODEX_HOME);
const preferredSessionSource = "vscode" as const;
const preferredOriginator = "Codex Desktop";
const defaultApprovalDecision: ApprovalDecision = "decline";
const echoVoiceTranscript = false;
const enableDraftStreaming = true;
const draftStreamingThrottleMs = 500;
const allowedChatIds = parseAllowedChatIds(process.env.TELEGRAM_ALLOWED_CHAT_IDS);

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
  onHelp: async (_, reply) => {
    await reply(HELP_TEXT, { reply_markup: quickActionsKeyboard() });
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
        if (echoVoiceTranscript) {
          await ctx.reply(`Voice transcript:\n\n${limitTelegramText(transcript)}`);
        }
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

console.log(
  `Telegram Codex bridge is running. Codex home: ${codexHome}. Session source override: ${preferredSessionSource}`
);
if (allowedChatIds) {
  console.log(`Telegram chat allowlist is active (${allowedChatIds.size} chat id${allowedChatIds.size === 1 ? "" : "s"}).`);
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
  await forceSessionSource(threadId, codexHome, preferredSessionSource, preferredOriginator);
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
