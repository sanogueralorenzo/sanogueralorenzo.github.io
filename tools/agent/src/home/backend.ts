import type { HomeEntry, SessionCard, TurnRequest } from "../conversation/types.js";

export type HomeAction =
  | { type: "start"; text?: string; title: string; cwd?: string }
  | { type: "continue"; text?: string; title: string; sessionId: string }
  | { type: "steer"; text: string; title: string; sessionId: string };

export interface HomeBackend {
  compose(request: TurnRequest, conversations: SessionCard[], entries: HomeEntry[], signal?: AbortSignal): Promise<HomeAction>;
  summarize(input: { title: string; request: string; output: string; state: "complete" | "failed" | "interrupted" }, signal?: AbortSignal): Promise<{ state: "ready" | "needs_input" | "failed"; summary: string }>;
}
