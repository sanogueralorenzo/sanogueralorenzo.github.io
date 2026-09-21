export const RUNTIME_PROTOCOL_VERSION = 1;
export type Channel = "cli" | "telegram" | "macos" | "api";

export interface Session {
  id: string;
  scopeKey: string;
  cwd: string | null;
  title: string;
  updatedAt: string;
}

export interface Message {
  role: "user" | "assistant" | "tool";
  content: string;
}

export interface SessionCard {
  id: string;
  title: string;
  updatedAt: string;
  context: string;
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
  | { type: "turn"; text: string; channel: Channel; hasAttachments: boolean }
  | { type: "session"; session: Session }
  | { type: "navigate"; session: Session; url: string }
  | ProgressEvent
  | { type: "done"; sessionId: string }
  | { type: "error"; message: string };

export interface RunInfo {
  id: string;
  origin: Channel;
}

export interface RunEnvelope {
  runId: string;
  event: RuntimeEvent;
}

export interface TurnRequest {
  text: string;
  attachmentIds?: string[];
  attachments?: Attachment[];
  cwd?: string;
  sessionId?: string;
  fresh?: boolean;
  channel?: Channel;
}

export interface RuntimeConfig {
  homeDir: string;
  port: number;
  codexCommand: string;
}
