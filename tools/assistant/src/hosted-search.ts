import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

function searchLabel(action?: { type?: string; query?: string; queries?: string[]; url?: string }): string {
  if (action?.type === "search") {
    const query = action.query || action.queries?.[0];
    return query?.trim() ? `Web search: ${query.trim()}` : "Web search";
  }
  if (action?.type === "open_page" && action.url) {
    try {
      const url = new URL(action.url);
      return `Opening: ${url.host.replace(/^www\./, "")}${url.pathname === "/" ? "" : url.pathname}`;
    } catch { /* Search references are not always URLs. */ }
  }
  return "Web search";
}

export function trackHostedSearch(pi: ExtensionAPI, report: (label: string) => void): void {
  pi.on("provider_stream_event", ({ data }) => {
    if (typeof data !== "object" || data === null) return;
    const event = data as { type?: string; item?: { type?: string; action?: { type?: string; query?: string; queries?: string[]; url?: string } } };
    if (event.item?.type !== "web_search_call") return;
    if (event.type === "response.output_item.added" || event.type === "response.output_item.done") report(searchLabel(event.item.action));
  });
}
