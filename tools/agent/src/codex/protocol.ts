export interface JsonRpcMessage {
  id?: number | string;
  method?: string;
  params?: Record<string, unknown>;
  result?: unknown;
  error?: { code: number; message: string; data?: unknown };
}

export interface CodexAccountStatus {
  account: { type: "apiKey" | "chatgpt" | "amazonBedrock"; planType?: string } | null;
}

export interface RateLimitSnapshot {
  limitName?: string | null;
  rateLimitReachedType?: string | null;
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
