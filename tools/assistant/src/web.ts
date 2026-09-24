import { isIP } from "node:net";
import { Type } from "typebox";
import type { ToolDefinition } from "@earendil-works/pi-coding-agent";

const entities: Record<string, string> = { amp: "&", lt: "<", gt: ">", quot: '"', apos: "'", nbsp: " ", mdash: "—", ndash: "–", hellip: "…" };
const decode = (value: string) => value.replace(/&#(?:x([\da-f]+)|(\d+));|&(amp|lt|gt|quot|apos|nbsp|mdash|ndash|hellip);/gi, (_match, hex, decimal, named) =>
  hex ? String.fromCodePoint(parseInt(hex, 16)) : decimal ? String.fromCodePoint(parseInt(decimal, 10)) : entities[named.toLowerCase()]);
const plain = (html: string) => decode(html.replace(/<[^>]*>/g, " ")).replace(/\s+/g, " ").trim();
function publicUrl(address: string | URL) {
  const url = new URL(address);
  const host = url.hostname.replace(/^\[|\]$/g, "");
  if (url.protocol !== "https:" || url.username || url.password || isIP(host) || host === "localhost" || host.endsWith(".localhost"))
    throw new Error("Open a public HTTPS page");
  return url;
}

async function fetchText(url: URL, signal?: AbortSignal) {
  let response: Response | undefined;
  for (let i = 0; i < 5; i++) {
    response = await fetch(url, { headers: { "user-agent": "Mozilla/5.0" }, redirect: "manual",
      signal: AbortSignal.any([AbortSignal.timeout(12_000), ...(signal ? [signal] : [])]) });
    if (response.status < 300 || response.status >= 400) break;
    const location = response.headers.get("location");
    if (!location) throw new Error("Web redirect has no destination");
    url = publicUrl(new URL(location, url));
  }
  if (!response || (response.status >= 300 && response.status < 400)) throw new Error("Too many web redirects");
  if (!response.ok) throw new Error(`Web request failed (${response.status})`);
  const type = response.headers.get("content-type") || "";
  if (!/text\/html|text\/plain|application\/xml|text\/xml/i.test(type)) throw new Error(`Cannot read ${type || "this page type"}`);
  const reader = response.body?.getReader();
  if (!reader) return { url: response.url, text: "" };
  const chunks: Uint8Array[] = [];
  let size = 0;
  try {
    while (size < 500_000) {
      const { value, done } = await reader.read();
      if (done) break;
      chunks.push(value);
      size += value.length;
    }
  } finally { await reader.cancel(); }
  return { url: response.url, text: new TextDecoder().decode(Buffer.concat(chunks).subarray(0, 500_000)) };
}

function resultUrl(href: string) {
  const url = new URL(decode(href));
  const encoded = url.hostname.endsWith("bing.com") ? url.searchParams.get("u") : null;
  if (encoded?.startsWith("a1")) return Buffer.from(encoded.slice(2), "base64url").toString("utf8");
  return url.href;
}

function webResults(text: string) {
  return [...text.matchAll(/<li class="b_algo"[^>]*>([\s\S]*?)(?=<li class="b_algo"|<\/ol>)/g)].flatMap(([, block]) => {
    const heading = block.match(/<h2\b[^>]*>\s*<a\b[^>]*href="([^"]+)"[^>]*>([\s\S]*?)<\/a>/i);
    if (!heading) return [];
    const snippet = block.match(/<p\b[^>]*>([\s\S]*?)<\/p>/i);
    try { return [{ title: plain(heading[2]), url: resultUrl(heading[1]), snippet: snippet ? plain(snippet[1]) : "" }]; }
    catch { return []; }
  }).filter((result) => result.title && /^https?:\/\//.test(result.url)).slice(0, 5);
}
function newsResults(text: string) {
  const cards = [...text.matchAll(/<div class="news-card newsitem[^>]*>/g)];
  return cards.flatMap((match, index) => {
    const tag = match[0];
    const link = tag.match(/\bdata-url="([^"]+)"/i)?.[1];
    const title = tag.match(/\bdata-title="([^"]+)"/i)?.[1];
    if (!link || !title) return [];
    const body = text.slice(match.index, cards[index + 1]?.index ?? match.index + 4000);
    const snippet = body.match(/<div class="snippet"[^>]*>([\s\S]*?)<\/div>/i)?.[1];
    const age = body.match(/aria-label="([^"]+ ago)"/i)?.[1];
    try { return [{ title: plain(title), url: resultUrl(link), snippet: snippet ? plain(snippet) : "", ...(age ? { age } : {}) }]; }
    catch { return []; }
  }).filter((result) => result.title && /^https?:\/\//.test(result.url)).slice(0, 5);
}
export async function searchWeb(query: string, signal?: AbortSignal) {
  const search = (path: string) => {
    const url = new URL(path, "https://www.bing.com");
    url.searchParams.set("q", query);
    url.searchParams.set("mkt", "en-US");
    return fetchText(url, signal);
  };
  const [web, news] = await Promise.allSettled([search("/search"), search("/news/search")]);
  const results = { news: news.status === "fulfilled" ? newsResults(news.value.text) : [],
    web: web.status === "fulfilled" ? webResults(web.value.text) : [] };
  if (!results.news.length && !results.web.length) throw new Error("Search returned no readable results");
  return { query, searchedAt: new Date().toISOString(), ...results };
}

export async function openWeb(address: string, signal?: AbortSignal) {
  const page = await fetchText(publicUrl(address), signal);
  const title = plain(page.text.match(/<title\b[^>]*>([\s\S]*?)<\/title>/i)?.[1] || "");
  const content = plain(page.text.replace(/<(script|style|nav|footer|header)\b[^>]*>[\s\S]*?<\/\1>/gi, " "));
  if (!content) throw new Error("This page has no readable text");
  return { url: page.url, title, text: content.slice(0, 14_000) };
}

const searchParams = Type.Object({ query: Type.String({ minLength: 2, maxLength: 200 }) });
const openParams = Type.Object({ url: Type.String() });
export const webTools: ToolDefinition[] = [
  {
    name: "web_search", label: "Search the web", description: "Search public web pages and recent news in one call. Open relevant results to verify details.",
    promptSnippet: "Search web pages and news in one call, then open relevant results before answering.",
    parameters: searchParams,
    execute: async (_id, { query }, signal) => ({ content: [{ type: "text", text: JSON.stringify(await searchWeb(query, signal)) }], details: undefined }),
  } as ToolDefinition<typeof searchParams>,
  {
    name: "web_open", label: "Read web page", description: "Read text from a public HTTPS page. Use a search result or user-provided URL and cite its URL in your answer.",
    parameters: openParams,
    execute: async (_id, { url }, signal) => ({ content: [{ type: "text", text: JSON.stringify(await openWeb(url, signal)) }], details: undefined }),
  } as ToolDefinition<typeof openParams>,
];
