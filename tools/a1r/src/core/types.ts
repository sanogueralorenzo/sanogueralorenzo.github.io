export type WorkKind = "personal" | "coding";
export type ModelTier = "fast" | "standard" | "deep";

export interface RouteDecision {
  kind: WorkKind;
  tier: ModelTier;
  reasons: string[];
  allowTools: boolean;
  allowDelegation: boolean;
}

export interface Session {
  id: string;
  scopeKey: string;
  kind: WorkKind;
  cwd: string | null;
  title: string;
  summary: string;
  createdAt: string;
  updatedAt: string;
}

export interface Message {
  id: number;
  sessionId: string;
  role: "user" | "assistant" | "tool";
  content: string;
  createdAt: string;
}

export interface Memory {
  id: number;
  scope: string;
  content: string;
  sourceSessionId: string | null;
  createdAt: string;
  updatedAt: string;
}

export type RuntimeEvent =
  | { type: "session"; session: Session; route: RouteDecision; model: string }
  | { type: "status"; message: string }
  | { type: "text_delta"; delta: string }
  | { type: "tool_start"; name: string; callId: string }
  | { type: "tool_end"; name: string; callId: string; summary: string }
  | { type: "done"; sessionId: string; responseId: string | null }
  | { type: "error"; message: string; recoverable: boolean };

export interface TurnRequest {
  text: string;
  cwd?: string;
  sessionId?: string;
  fresh?: boolean;
  channel?: "cli" | "telegram" | "macos" | "api";
  senderId?: string;
}

export interface RuntimeConfig {
  homeDir: string;
  host: string;
  port: number;
  models: Record<ModelTier, string>;
  maxToolRounds: number;
  maxHistoryMessages: number;
  telegramToken?: string;
  telegramOwnerId?: string;
}
