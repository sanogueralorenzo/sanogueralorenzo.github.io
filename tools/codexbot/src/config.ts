import { isAbsolute, resolve } from "node:path";
import { homedir } from "node:os";
import process from "node:process";
import { config as loadEnv } from "dotenv";
import { ApprovalDecision, ApprovalPolicy, SandboxMode } from "./adapters/app-server/client.js";
import { expandHomePath } from "./shared/path-utils.js";

type RuntimeConfig = {
  token: string;
  bindingFile: string;
  allowedChatIds: Set<string>;
  defaultApprovalDecision: ApprovalDecision;
  userHome: string;
};

export function loadRuntimeConfig(): RuntimeConfig {
  loadEnv();

  const token = mustGetEnv("TELEGRAM_BOT_TOKEN");
  const userHome = homedir();
  const bindingFile = resolve(process.cwd(), "runtime/bindings.json");

  return {
    token,
    bindingFile,
    allowedChatIds: parseRequiredAllowedChatIds(process.env.TELEGRAM_ALLOWED_CHAT_IDS),
    defaultApprovalDecision: "decline",
    userHome,
  };
}

export function getConversationOptionsFromEnv(userHome: string): {
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

function mustGetEnv(name: string): string {
  const value = process.env[name];
  if (!value) {
    throw new Error(`Missing required env var: ${name}`);
  }
  return value;
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

function parseRequiredAllowedChatIds(value?: string): Set<string> {
  const items = (value ?? "")
    .split(",")
    .map((part) => part.trim())
    .filter((part) => part.length > 0);

  const allowedChatIds = new Set(items);
  if (allowedChatIds.size === 0) {
    throw new Error(
      "Missing required env var: TELEGRAM_ALLOWED_CHAT_IDS. Refusing to start without an explicit Telegram chat allowlist."
    );
  }

  return allowedChatIds;
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
