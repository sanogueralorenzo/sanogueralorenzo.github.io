import type { CodexEvent } from "./types.js";

export class EventHub {
  private readonly subscribers = new Map<string, Set<(event: CodexEvent) => void>>();

  subscribe(sessionId: string, listener: (event: CodexEvent) => void): () => void {
    const listeners = this.subscribers.get(sessionId) ?? new Set<(event: CodexEvent) => void>();
    listeners.add(listener);
    this.subscribers.set(sessionId, listeners);
    return () => {
      listeners.delete(listener);
      if (listeners.size === 0) this.subscribers.delete(sessionId);
    };
  }

  publish(event: CodexEvent): void {
    for (const listener of this.subscribers.get(event.sessionId) ?? []) {
      listener(event);
    }
  }
}
