export interface JsonRpcMessage {
  id?: number | string;
  method?: string;
  params?: Record<string, unknown>;
  result?: unknown;
  error?: { code: number; message: string };
}

export interface CodexAccountStatus {
  account: { type: "apiKey" | "chatgpt" | "amazonBedrock" } | null;
}

export type CodexAuthMode = "apiKey" | "chatgpt";

export type CodexLoginMode = "browser" | "headless";

export type CodexLoginStart =
  | { type: "chatgpt"; loginId: string; authUrl: string }
  | { type: "chatgptDeviceCode"; loginId: string; verificationUrl: string; userCode: string };

export interface CodexLoginResult {
  state: "pending" | "complete" | "failed";
  error?: string;
}
