import { setTimeout as delay } from "node:timers/promises";
import { Agent as Dispatcher, fetch as fetchEvents } from "undici";
import type { Agent } from "../src/agent.ts";
import type { Data } from "../src/state.ts";

export type Conversation = ReturnType<Agent["transcript"]>;
type Event =
  | { type: "snapshot"; data: Data }
  | { type: "providers" }
  | { type: "progress"; sourceId: string; text: string }
  | ({ type: "conversation"; sessionId: string } & Conversation);

export function agentClient(url: URL, signal: AbortSignal) {
  async function request(path: string, body: object) {
    const response = await fetch(new URL(`/api/${path}`, url), {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify(body),
      signal,
    });
    const result = await response.json();
    if (!response.ok) throw new Error(result.error || `Request failed (${response.status})`);
  }

  async function follow(receive: (event: Event) => void, connected: (online: boolean) => void) {
    const dispatcher = new Dispatcher({ bodyTimeout: 0 });
    try {
      while (!signal.aborted) {
        try {
          const response = await fetchEvents(new URL("/api/events", url), { signal, dispatcher });
          if (!response.ok || !response.body) {
            await response.body?.cancel();
            throw new Error(`Event stream unavailable (${response.status})`);
          }
          connected(true);
          const decoder = new TextDecoder();
          let buffer = "";
          for await (const chunk of response.body) {
            buffer += decoder.decode(chunk, { stream: true });
            const frames = buffer.split("\n\n");
            buffer = frames.pop() ?? "";
            for (const frame of frames) {
              if (frame.startsWith("data: ")) receive(JSON.parse(frame.slice(6)) as Event);
            }
          }
        } catch {}
        if (signal.aborted) return;
        connected(false);
        await delay(1000, undefined, { signal }).catch(() => {});
      }
    } finally {
      await dispatcher.destroy();
    }
  }

  return { request, follow };
}
