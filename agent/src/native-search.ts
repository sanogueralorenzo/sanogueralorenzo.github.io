import type { AssistantMessage } from "@earendil-works/pi-ai";

export class NativeSearchSources {
  private readonly sources = new Map<string, string>();
  observe(value: unknown) {
    if (!value || typeof value !== "object" || !("url" in value) || typeof value.url !== "string") return;
    try {
      const url = new URL(value.url);
      if (!["https:", "http:"].includes(url.protocol)) return;
      const title = "title" in value && typeof value.title === "string" ? value.title.trim() : "";
      this.sources.set(url.href, title || url.hostname);
    } catch {}
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
