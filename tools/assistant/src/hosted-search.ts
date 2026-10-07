export function hostedSearchLabel(data: unknown): string | undefined {
  if (typeof data !== "object" || data === null) return;
  const event = data as { type?: string; item?: { type?: string; action?: { type?: string; query?: string; queries?: string[]; url?: string } } };
  if (event.item?.type !== "web_search_call" || !["response.output_item.added", "response.output_item.done"].includes(event.type || "")) return;
  const action = event.item.action;
  if (action?.type === "search") {
    const query = action.query || action.queries?.[0];
    return query?.trim() ? `Web search: ${query.trim()}` : "Web search";
  }
  if (action?.type === "open_page" && action.url) {
    try {
      const url = new URL(action.url);
      return `Opening: ${url.host.replace(/^www\./, "")}${url.pathname === "/" ? "" : url.pathname}`;
    } catch { /* Provider search references need not be URLs. */ }
  }
  return "Web search";
}
