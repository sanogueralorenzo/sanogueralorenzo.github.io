export type WorkKind = "personal" | "coding";
export type WorkerKind = "bounded" | "coding" | "astra";
export type BackendKind = "codex" | "responses";

export interface RouteDecision {
  kind: WorkKind;
  worker: WorkerKind | null;
  reasons: string[];
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
  | { type: "session"; session: Session; route: RouteDecision; model: string; backend: BackendKind }
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
  models: {
    coordinator: "gpt-5.6-luna";
    bounded: "gpt-5.6-luna";
    coding: "gpt-5.6-sol";
    astra: "gpt-6-astra";
  };
  maxToolRounds: number;
  maxHistoryMessages: number;
  codexCommand: string;
}
