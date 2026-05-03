export type SessionStatus = "idle" | "running" | "failed" | "cancelled";

export type CodexSession = {
  id: string;
  title: string;
  cwd: string;
  codexThreadId: string | null;
  status: SessionStatus;
  createdAt: string;
  updatedAt: string;
  lastEventId: number;
};

export type CodexEventType =
  | "session.created"
  | "session.updated"
  | "message.user"
  | "turn.started"
  | "assistant.output"
  | "tool.output"
  | "codex.event"
  | "final.answer"
  | "turn.failed"
  | "turn.cancelled"
  | "session.deleted";

export type CodexEvent = {
  id: number;
  sessionId: string;
  type: CodexEventType;
  createdAt: string;
  data?: Record<string, unknown>;
  raw?: Record<string, unknown>;
};

export type StoreSnapshot = {
  sessions: CodexSession[];
};

export type CreateSessionBody = {
  title?: string;
  cwd?: string;
  codexThreadId?: string;
};

export type MessageBody = {
  text?: string;
};

export type CodexInfo = {
  available: boolean;
  path?: string;
  version?: string;
  error?: string;
  capabilities: {
    transport: "sse";
    sessions: true;
    cancellation: true;
    rawEvents: true;
  };
};
