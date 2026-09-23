import { escapeHTML, icon, renderMarkdown } from "../view.js";

export function renderHome(state) {
  const homeEntries = [...state.homeEntries].sort((a, b) => a.updatedAt.localeCompare(b.updatedAt));
  return `<main class="home-scroll scroll-area"><div class="home-content">${homeEntries.length
    ? homeEntries.map(renderHomeEntry).join("")
    : `<div class="empty-home-chat"><span class="brand-mark">${icon("sparkle", 17)}</span><strong>How can I help?</strong><p>Ask me anything or give me a task.</p></div>`}
  </div></main>`;
}

function renderHomeEntry(entry) {
  const requests = entry.requests?.length ? entry.requests : [{ text: entry.body }];
  const messages = requests.map(({ text }) => `<div class="message-row user-row"><${entry.sessionId ? "button" : "div"} class="message-bubble user-bubble home-entry" ${entry.sessionId ? `data-action="open-session" data-session="${escapeHTML(entry.sessionId)}" title="Open conversation"` : ""}><div class="message-text markdown-content">${renderMarkdown(text)}</div></${entry.sessionId ? "button" : "div"}></div>`).join("");
  const reply = entry.summary
    ? `<article class="message-row assistant-row"><div class="message-bubble assistant-bubble"><div class="message-text markdown-content">${renderMarkdown(entry.summary)}</div></div></article>`
    : "";
  const progress = entry.state === "routing" || entry.state === "working"
    ? `<div class="home-progress"><i class="spinner"></i><span>${entry.state === "routing" ? "Finding the right specialist…" : "Working on your task…"}</span></div>`
    : "";
  return `<section class="home-exchange">${messages}${progress}${reply}</section>`;
}
