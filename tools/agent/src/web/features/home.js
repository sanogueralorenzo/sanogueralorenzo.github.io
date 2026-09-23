import { escapeHTML, icon, renderInlineMarkdown, renderMarkdown } from "../view.js";

export function renderHome(state) {
  const codex = state.setupStatus?.codex;
  const codexStatus = !state.setupStatus ? "Checking connection…" : codex.connected ? "Connected" : codex.installed ? "Available" : "Not installed";
  const homeEntries = [...state.homeEntries].sort((a, b) => a.updatedAt.localeCompare(b.updatedAt));
  return `<div class="home-scroll scroll-area"><div class="home-content">
    <section class="welcome-card">
      <div class="eyebrow">${icon("sparkle", 15)}<span>Your coordination space</span></div>
      <h1>What can I help you get moving?</h1>
      <p>Send a task to the right specialist, then follow the work here.</p>
      <ul><li>Delegate a focused task</li><li>Get concise progress updates</li><li>Open a session to continue the conversation</li></ul>
    </section>
    <section class="workspace-card">
      <h2>Your workspace</h2>
      ${workspaceRow("connection", "Agent runtime", state.isConnected ? "Ready for tasks" : "Connecting…", state.isConnected)}
      <div class="card-divider"></div>
      ${workspaceRow("terminal", "Codex", codexStatus, codex?.connected === true)}
    </section>
    <section class="recent-tasks">
      <div class="section-heading"><h2>Recent tasks</h2>${homeEntries.length ? `<span class="count-badge">${homeEntries.length}</span>` : ""}</div>
      ${homeEntries.length ? homeEntries.map(renderHomeEntry).join("") : '<p class="empty-card">Your dispatched tasks will show up here.</p>'}
    </section>
  </div></div>`;
}

function workspaceRow(symbol, title, detail, ready) {
  return `<div class="workspace-row"><span class="workspace-icon">${icon(symbol, 16)}</span><span class="workspace-copy"><strong>${escapeHTML(title)}</strong><small>${escapeHTML(detail)}</small></span><span class="connection-mark ${ready ? "connected" : ""}">${icon(ready ? "check-circle" : "circle", 15)}</span></div>`;
}

function renderHomeEntry(entry) {
  const status = entry.state === "routing" || entry.state === "working" ? '<span class="state-chip working"><i class="spinner"></i></span>'
    : entry.state === "ready" ? '<span class="state-chip">👍</span>'
    : entry.state === "needs_input" ? '<span class="state-chip">💬</span>'
    : entry.state === "failed" ? '<span class="state-chip">⚠️</span>' : "";
  const requests = entry.requests?.length ? entry.requests : [{ text: entry.body }];
  const messages = requests.map(({ text }, index) => `<button class="home-entry" data-action="open-session" data-session="${escapeHTML(entry.sessionId ?? "")}" ${entry.sessionId ? "" : "disabled"}><span class="entry-copy"><span class="message-text markdown-content">${renderMarkdown(text)}</span></span>${index === requests.length - 1 ? status : ""}</button>`).join("");
  const reply = entry.summary
    ? `<article class="message-row assistant-row"><div class="message-bubble assistant-bubble"><div class="message-text markdown-content">${renderMarkdown(entry.summary)}</div></div></article>`
    : "";
  return `<div class="home-exchange">${messages}${reply}</div>`;
}

export function renderBottomBar() {
  return `<nav class="bottom-bar" aria-label="Main navigation"><button class="bottom-item selected" data-action="home" disabled>${icon("home-fill", 15)}<span>Home</span></button><button class="bottom-item" data-action="toggle-sessions">${icon("clock", 15)}<span>Sessions</span></button></nav>`;
}
