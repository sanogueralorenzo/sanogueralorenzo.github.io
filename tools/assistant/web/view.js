export function escapeHTML(value = "") {
  return String(value).replace(/[&<>"']/g, (character) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[character]);
}

export function icon(name, size = 18) {
  const paths = {
    add: '<path d="M12 5v14M5 12h14"/>',
    back: '<path d="m10 18-6-6 6-6"/><path d="M4 12h16"/>',
    check: '<path d="m5 12 4 4L19 6"/>',
    close: '<path d="m18 6-12 12M6 6l12 12"/>',
    circle: '<circle cx="12" cy="12" r="9"/>',
    "check-circle": '<circle cx="12" cy="12" r="9" fill="currentColor"/><path d="m8 12 2.5 2.5L16.5 8.5" stroke="var(--canvas)" stroke-width="2.2"/>',
    connection: '<circle cx="12" cy="5" r="2.5"/><circle cx="5" cy="18" r="2.5"/><circle cx="19" cy="18" r="2.5"/><path d="m10.7 7.2-4.4 8.6m7-8.6 4.4 8.6M7.5 18h9"/>',
    edit: '<path d="m16 4 4 4L9 19l-5 1 1-5L16 4Z"/><path d="m14 6 4 4"/>',
    file: '<path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"/><path d="M14 2v6h6"/>',
    grid: '<rect x="3" y="3" width="7" height="7" rx="1"/><rect x="14" y="3" width="7" height="7" rx="1"/><rect x="3" y="14" width="7" height="7" rx="1"/><rect x="14" y="14" width="7" height="7" rx="1"/>',
    mic: '<rect x="9" y="2" width="6" height="12" rx="3"/><path d="M5 10v2a7 7 0 0 0 14 0v-2M12 19v3m-4 0h8"/>',
    pin: '<path d="m16 3 5 5-4 1-4 4-1 4-2-2-4 4"/><path d="m8 8 8 8"/>',
    plus: '<path d="M12 5v14M5 12h14"/>',
    reply: '<path d="m9 17-5-5 5-5"/><path d="M4 12h10a6 6 0 0 1 6 6"/>',
    send: '<path d="m5 12 14-7-4 14-3-6z"/><path d="m12 13 7-8"/>',
    settings: '<path d="M12 8a4 4 0 1 0 0 8 4 4 0 0 0 0-8Z"/><path d="m19.4 15 .1.1 1.4 1.1-1.4 2.4-1.7-.7a8 8 0 0 1-1.6.9L16 21h-2.8l-.3-1.9a8 8 0 0 1-1.8 0L10.8 21H8l-.2-2.2a8 8 0 0 1-1.6-.9l-1.7.7-1.4-2.4 1.4-1.1a8 8 0 0 1 0-1.8l-1.4-1.1 1.4-2.4 1.7.7a8 8 0 0 1 1.6-.9L8 7h2.8l.3 1.9a8 8 0 0 1 1.8 0L13.2 7H16l.2 2.2a8 8 0 0 1 1.6.9l1.7-.7 1.4 2.4-1.4 1.1a8 8 0 0 1 0 2.1Z"/>',
    sparkle: '<path d="m12 3 1.9 5.8L20 11l-6.1 2.1L12 19l-1.9-5.9L4 11l6.1-2.2L12 3Z"/><path d="m19 15 .8 2.2L22 18l-2.2.8L19 21l-.8-2.2L16 18l2.2-.8L19 15Z"/>',
    stop: '<rect x="5" y="5" width="14" height="14" rx="2"/>',
    terminal: '<rect x="3" y="4" width="18" height="16" rx="2"/><path d="m7 9 3 3-3 3m6 0h4"/>',
  };
  return `<svg width="${size}" height="${size}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${paths[name] ?? paths.sparkle}</svg>`;
}

export function renderInlineMarkdown(value) {
  const code = [];
  let text = escapeHTML(value).replace(/`([^`]+)`/g, (_match, content) => {
    const marker = `\u0000${code.length}\u0000`;
    code.push(`<code>${content}</code>`);
    return marker;
  });
  text = text.replace(/\[([^\]]+)\]\(([^\s)]+)(?:\s+"([^"]*)")?\)/g, (_match, label, href, title) => {
    let safeHref;
    try {
      const rawHref = href.replace(/&(?:amp|lt|gt|quot|#39);/g, (entity) => ({ "&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": '"', "&#39;": "'" })[entity] ?? entity);
      const url = new URL(rawHref, window.location.origin);
      if (!["http:", "https:", "mailto:"].includes(url.protocol)) return label;
      safeHref = escapeHTML(url.href);
    } catch { return label; }
    const rendered = `<a href="${safeHref}"${title ? ` title="${escapeHTML(title)}"` : ""} target="_blank" rel="noreferrer">${label}</a>`;
    const marker = `\u0000${code.length}\u0000`;
    code.push(rendered);
    return marker;
  });
  text = text.replace(/\*\*([^*]+)\*\*/g, "<strong>$1</strong>")
    .replace(/__([^_]+)__/g, "<strong>$1</strong>")
    .replace(/~~([^~]+)~~/g, "<del>$1</del>")
    .replace(/(^|[^*])\*([^*\n]+)\*/g, "$1<em>$2</em>")
    .replace(/(^|[^_])_([^_\n]+)_/g, "$1<em>$2</em>");
  return text.replace(/\u0000(\d+)\u0000/g, (_match, index) => code[Number(index)] ?? "").replaceAll("\n", "<br>");
}

export function renderMarkdown(value = "") {
  const lines = String(value).replaceAll("\r\n", "\n").split("\n");
  const blocks = [];
  let paragraph = [];
  let list = null;
  let code = null;
  const flushParagraph = () => {
    if (paragraph.length) blocks.push(`<p>${paragraph.map(renderInlineMarkdown).join("<br>")}</p>`);
    paragraph = [];
  };
  const flushList = () => {
    if (list) blocks.push(`<${list.type}>${list.items.map((item) => `<li>${renderInlineMarkdown(item)}</li>`).join("")}</${list.type}>`);
    list = null;
  };

  for (const line of lines) {
    if (code) {
      if (/^\s*```/.test(line)) {
        blocks.push(`<pre><code>${escapeHTML(code.join("\n"))}</code></pre>`);
        code = null;
      } else code.push(line);
      continue;
    }
    if (/^\s*```/.test(line)) {
      flushParagraph();
      flushList();
      code = [];
      continue;
    }
    const heading = line.match(/^\s{0,3}(#{1,6})\s+(.+?)\s*#*\s*$/);
    const quote = line.match(/^\s*>\s?(.*)$/);
    const item = line.match(/^\s{0,3}([-*+] |\d+\. )(.*)$/);
    if (heading || quote || item || !line.trim()) flushParagraph();
    if (heading) {
      flushList();
      const level = heading[1].length;
      blocks.push(`<h${level}>${renderInlineMarkdown(heading[2])}</h${level}>`);
    } else if (quote) {
      flushList();
      blocks.push(`<blockquote>${renderInlineMarkdown(quote[1])}</blockquote>`);
    } else if (item) {
      const type = /^\s*\d+\./.test(line) ? "ol" : "ul";
      if (list?.type !== type) flushList();
      if (!list) list = { type, items: [] };
      list.items.push(item[2]);
    } else if (!line.trim()) flushList();
    else {
      flushList();
      paragraph.push(line);
    }
  }
  if (code) blocks.push(`<pre><code>${escapeHTML(code.join("\n"))}</code></pre>`);
  flushParagraph();
  flushList();
  return blocks.join("");
}

export function renderMessage(message) {
  if (message.role === "notice") return `<div class="notice">${escapeHTML(message.text)}</div>`;
  const artifacts = (message.artifacts ?? []).map((artifact) => artifact.kind === "image"
    ? `<a class="artifact image-artifact" href="/v1/artifacts/${encodeURIComponent(artifact.id)}" target="_blank" rel="noreferrer"><img src="/v1/artifacts/${encodeURIComponent(artifact.id)}" alt="${escapeHTML(artifact.name)}"><span>${escapeHTML(artifact.name)}</span></a>`
    : `<a class="artifact file-artifact" href="/v1/artifacts/${encodeURIComponent(artifact.id)}" target="_blank" rel="noreferrer">${icon("file", 16)}<span>${escapeHTML(artifact.name)}</span></a>`).join("");
  return `<article class="message-row ${message.role === "user" ? "user-row" : "assistant-row"}"><div class="message-bubble ${message.role === "user" ? "user-bubble" : "assistant-bubble"}">${message.text ? `<div class="message-text markdown-content">${renderMarkdown(message.text)}</div>` : message.role === "assistant" && !artifacts ? '<span class="typing-dots"><i></i><i></i><i></i></span>' : ""}${artifacts}</div></article>`;
}
