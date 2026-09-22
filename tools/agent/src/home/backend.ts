import type { SessionCard, TaskReport, TurnRequest } from "../conversation/types.js";

export type HomeAction =
  | { type: "start"; text: string; title: string; cwd?: string }
  | { type: "continue"; text: string; sessionId: string };

export interface HomeBackend {
  compose(request: TurnRequest, conversations: SessionCard[], reports: TaskReport[], signal?: AbortSignal): Promise<HomeAction[]>;
  summarize(input: { title: string; request: string; output: string; state: "complete" | "failed" | "interrupted" }, signal?: AbortSignal): Promise<Pick<TaskReport, "state" | "summary">>;
}
