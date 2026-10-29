import type { Api, AssistantMessage, Model } from "@earendil-works/pi-ai";

type Source = { url?: string; uri?: string; title?: string };
type SearchEvent = {
  annotation?: Source;
  delta?: { citation?: Source };
  item?: { content?: { annotations?: Source[] }[] };
  candidates?: { groundingMetadata?: { groundingChunks?: { web?: Source }[] } }[];
};

// Pi's normalized text omits these provider citation/grounding fields.
export class NativeSearchSources {
  private readonly sources = new Map<string, string>();
  observe(value: unknown) {
    if (!value || typeof value !== "object") return;
    const event = value as SearchEvent;
    const sources = [event.annotation, event.delta?.citation,
      ...(event.item?.content || []).flatMap(block => block.annotations || []),
      ...(event.candidates || []).flatMap(candidate => (candidate.groundingMetadata?.groundingChunks || []).map(chunk => chunk.web))];
    for (const source of sources) {
      const address = source?.url || source?.uri;
      if (!address) continue;
      try {
        const url = new URL(address);
        if (!["https:", "http:"].includes(url.protocol)) continue;
        this.sources.set(url.href, source?.title?.trim() || url.hostname);
      } catch {}
    }
  }
  append(message: AssistantMessage) {
    if (message.stopReason !== "stop") return;
    const text = message.content.filter(part => part.type === "text").map(part => part.text).join("\n");
    if (!text) return;
    const links = [...this.sources].filter(([url]) => !text.includes(url)).map(([url, title]) => {
      const label = title.replace(/\s+/g, " ").replace(/[\[\]\\]/g, "\\$&");
      return `[${label}](${url.replaceAll("(", "%28").replaceAll(")", "%29")})`;
    });
    if (links.length) message.content.push({ type: "text", text: `\n\nSources: ${links.join(", ")}` });
  }
}

// Hosted tools run at the provider, without opening a browser on the user's computer.
export function nativeSearchPayload(model: Model<Api>, payload: unknown, enabled: boolean): unknown {
  const responses = ["openai", "xai"].includes(model.provider) && model.api === "openai-responses";
  const anthropic = model.provider === "anthropic" && model.api === "anthropic-messages";
  const google = model.provider === "google" && model.api === "google-generative-ai" &&
    ["gemini-4-argon", "gemini-3.8-flash", "gemini-3.5-flash-lite"].includes(model.id);
  if (!responses && !anthropic && !google) return payload;
  if (!payload || typeof payload !== "object" || Array.isArray(payload)) throw new Error("Unexpected search request payload");
  const request = payload as Record<string, unknown>;
  if (google) {
    const config = request.config as Record<string, unknown>;
    const tools = (Array.isArray(config.tools) ? config.tools : []).map(({ googleSearch: _search, ...tool }) => tool)
      .filter(tool => Object.keys(tool).length);
    return { ...request, config: { ...config, tools: [...tools, ...(enabled ? [{ googleSearch: {} }] : [])] } };
  }
  const tools = (Array.isArray(request.tools) ? request.tools : []).filter(tool =>
    typeof tool.type !== "string" || !tool.type.startsWith("web_search"));
  const search = responses ? { type: "web_search" } : { type: "web_search_20250305", name: "web_search" };
  return { ...request, tools: [...tools, ...(enabled ? [search] : [])] };
}
