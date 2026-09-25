import { AsyncLocalStorage } from "node:async_hooks";
import type { ModelRuntime } from "@earendil-works/pi-coding-agent";

const activity = new AsyncLocalStorage<() => void>();

export function withSearchActivity<T>(report: () => void, run: () => Promise<T>): Promise<T> {
  return activity.run(report, run);
}

function observeSearch(response: Response, report: () => void): Response {
  if (!response.ok || !response.body) return response;
  const decoder = new TextDecoder();
  let buffer = "";
  const inspect = (frame: string) => {
    const data = frame.split("\n").filter((line) => line.startsWith("data:")).map((line) => line.slice(5).trim()).join("\n");
    if (!data.includes("web_search_call")) return;
    let event: { type?: string; item?: { type?: string } };
    try { event = JSON.parse(data); } catch { return; }
    if (event.type === "response.output_item.added" && event.item?.type === "web_search_call") report();
  };
  const stream = response.body.pipeThrough(new TransformStream<Uint8Array, Uint8Array>({
    transform(chunk, controller) {
      controller.enqueue(chunk);
      buffer = (buffer + decoder.decode(chunk, { stream: true })).replaceAll("\r\n", "\n");
      let end = buffer.indexOf("\n\n");
      while (end >= 0) {
        inspect(buffer.slice(0, end));
        buffer = buffer.slice(end + 2);
        end = buffer.indexOf("\n\n");
      }
    },
  }));
  return new Response(stream, { status: response.status, statusText: response.statusText, headers: response.headers });
}

export function enableHostedSearch(runtime: ModelRuntime): void {
  const provider = runtime.getProvider("openai-codex");
  if (!provider) throw new Error("Codex provider is unavailable");
  runtime.registerNativeProvider({ ...provider,
    streamSimple(model, context, options) {
      const report = activity.getStore();
      if (!report) return provider.streamSimple(model, context, options);
      // Pi omits hosted calls from its public events; observe the same response stream.
      return provider.streamSimple(model, context, { ...options, transport: "sse",
        fetch: async (input, init) => observeSearch(await (options?.fetch || fetch)(input, init), report) });
    },
  });
}
