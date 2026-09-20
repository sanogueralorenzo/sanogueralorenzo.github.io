export interface JsonRpcResponse {
  id: number | string;
  result?: unknown;
  error?: { code: number; message: string; data?: unknown };
}

export interface JsonRpcMessage {
  id?: number | string;
  method?: string;
  params?: Record<string, unknown>;
  result?: unknown;
  error?: { code: number; message: string; data?: unknown };
}

export interface CodexAccount {
  type: "apiKey" | "chatgpt" | "amazonBedrock";
  email?: string | null;
  planType?: string;
}

export interface CodexAccountStatus {
  account: CodexAccount | null;
  requiresOpenaiAuth: boolean;
}

export interface RateLimitWindow {
  usedPercent: number;
  windowDurationMins: number | null;
  resetsAt: number | null;
}

export interface RateLimitSnapshot {
  limitId: string | null;
  limitName: string | null;
  primary: RateLimitWindow | null;
  secondary: RateLimitWindow | null;
  planType: string | null;
  rateLimitReachedType: string | null;
  credits?: { hasCredits: boolean; unlimited: boolean; balance: string | null } | null;
}

export interface CodexRateLimits {
  ordinaryUsageAllowed: boolean | null;
  rateLimits: RateLimitSnapshot;
  rateLimitsByLimitId: Record<string, RateLimitSnapshot> | null;
}

export type CodexLoginMode = "browser" | "headless";

export type CodexLoginStart =
  | { type: "chatgpt"; loginId: string; authUrl: string }
  | { type: "chatgptDeviceCode"; loginId: string; verificationUrl: string; userCode: string };

export interface CodexLoginResult {
  state: "pending" | "complete" | "failed";
  error?: string;
}
