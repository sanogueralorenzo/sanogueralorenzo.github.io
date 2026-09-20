export type WorkKind = "personal" | "coding";
export type WorkerKind = "bounded" | "coding" | "astra";
export type BackendKind = "codex" | "responses";

export interface RouteDecision {
  kind: WorkKind;
  worker: WorkerKind | null;
}

export interface Session {
  id: string;
  scopeKey: string;
  kind: WorkKind;
  cwd: string | null;
  title: string;
  updatedAt: string;
}

export interface Message {
  role: "user" | "assistant" | "tool";
  content: string;
}

export interface Memory {
  content: string;
}

interface StoredFile {
  id: string;
  name: string;
  mimeType: string;
  size: number;
  path: string;
}

export interface Attachment extends StoredFile {}

export interface Artifact extends StoredFile {
  kind: "image" | "file";
}

export type ProgressEvent =
  | { type: "status"; message: string }
  | { type: "text_delta"; delta: string }
  | { type: "artifact"; artifact: Artifact }
  | { type: "tool_start"; name: string; callId: string }
  | { type: "tool_end"; name: string; callId: string; summary: string };

export type RuntimeEvent =
  | { type: "session"; session: Session }
  | ProgressEvent
  | { type: "done"; sessionId: string }
  | { type: "error"; message: string };

export interface TurnRequest {
  text: string;
  attachmentIds?: string[];
  attachments?: Attachment[];
  cwd?: string;
  sessionId?: string;
  fresh?: boolean;
  channel?: "cli" | "telegram" | "macos" | "api";
}

export interface RuntimeConfig {
  homeDir: string;
  port: number;
  codexCommand: string;
}
