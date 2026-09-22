export const RUNTIME_PROTOCOL_VERSION = 1;
export const HOME_SESSION_ID = "home";
export type Channel = "cli" | "telegram" | "macos" | "api";

export interface Session {
  id: string;
  cwd: string | null;
  title: string;
  updatedAt: string;
}

export interface SessionStatus extends Session {
  activeRunId: string | null;
}

export interface Message {
  role: "user" | "assistant" | "tool";
  content: string;
}

export interface SessionCard {
  id: string;
  cwd: string | null;
  title: string;
  updatedAt: string;
  preview: string;
}

export interface HomeEntry {
  id: string;
  sessionId: string | null;
  title: string | null;
  body: string;
  summary: string | null;
  state: "routing" | "working" | "ready" | "needs_input" | "failed" | null;
  url: string | null;
  updatedAt: string;
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
  | { type: "session_activity"; sessionId: string; runId: string | null }
  | { type: "session"; session: Session }
  | { type: "navigate"; session: Session; url: string; continues: boolean }
  | { type: "home_entry"; entry: HomeEntry }
  | { type: "steer"; text: string; channel: Channel }
  | { type: "task_queued"; sessionId: string }
  | ProgressEvent
  | { type: "done"; sessionId: string }
  | { type: "error"; message: string };

export interface RunInfo {
  id: string;
  sessionId: string;
  origin: Channel;
}

export interface RunSnapshot {
  run: RunInfo;
  turn: Extract<RuntimeEvent, { type: "turn" }>;
  session: Session | null;
  output: string;
  artifacts: Artifact[];
  navigation: Extract<RuntimeEvent, { type: "navigate" }> | null;
}

export interface LastRun {
  id: string;
  sessionId: string;
  state: "running" | "complete" | "interrupted" | "failed";
  output: string;
}

export interface RuntimeSnapshot {
  sessions: SessionStatus[];
  homeEntries: HomeEntry[];
  transcript: { session: Session; messages: Message[] } | null;
  activeRuns: RunSnapshot[];
  lastRuns: Pick<LastRun, "id" | "sessionId" | "state">[];
}

export type StreamEvent = RuntimeEvent | { type: "snapshot"; snapshot: RuntimeSnapshot };

export interface RunEnvelope {
  sessionId: string;
  runId: string;
  event: StreamEvent;
}

export interface TurnRequest {
  text: string;
  requestId?: string;
  attachmentIds?: string[];
  attachments?: Attachment[];
  cwd?: string;
  sessionId?: string;
  channel?: Channel;
  queuedTaskId?: string;
}

export interface RuntimeConfig {
  homeDir: string;
  port: number;
  codexCommand: string;
}
