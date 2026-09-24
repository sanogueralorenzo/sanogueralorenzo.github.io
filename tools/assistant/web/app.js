import { escapeHTML, icon, renderMarkdown, renderMessage } from "./view.js";

const root = document.querySelector("#app");
const state = { data: { messages: [], entries: [], sessions: [], turns: [] }, selected: localStorage.getItem("assistant-view") || "home",
  transcript: [], input: "", homeDraft: "", sessionDrafts: {}, scroll: { home: 0 }, error: "", connected: false, streaming: "", activity: "", steer: false };
let renderedView = state.selected;

async function api(path, method = "GET", body) {
  const response = await fetch(path, { method, headers: body ? { "content-type": "application/json" } : {}, body: body ? JSON.stringify(body) : undefined });
  const result = await response.json();
  if (!response.ok) throw new Error(result.error || `Request failed (${response.status})`);
  return result;
}

function statusBadge(value) {
  const status = value || "routing";
  const symbol = ({ ready: "👍", failed: "⚠️", interrupted: "⏸️" })[status];
  const working = status === "routing" || status === "queued" || status === "working";
  return `<span class="state-chip ${working ? "working" : ""}" role="img" aria-label="${escapeHTML(status.replace("_", " "))}">${working ? '<i class="spinner"></i>' : symbol || ""}</span>`;
}
function home() {
  if (!state.data.messages.length) return `<main class="home-scroll scroll-area"><div class="home-content"><div class="empty-home-chat"><span class="brand-mark">${icon("sparkle", 17)}</span><strong>How can I help?</strong><p>Ask me anything or give me a task.</p></div></div></main>`;
  return `<main class="home-scroll scroll-area"><div class="home-content">${state.data.messages.map((message) => {
    const entry = state.data.entries.find((item) => item.id === message.entryId);
    const request = `<${entry?.sessionId ? "button" : "div"} class="message-bubble user-bubble home-entry" ${entry?.sessionId ? `data-action="open" data-session="${escapeHTML(entry.sessionId)}"` : ""}><span class="entry-copy">${escapeHTML(message.text)}</span>${statusBadge(entry?.status)}</${entry?.sessionId ? "button" : "div"}>`;
    const updates = entry?.updates.filter((update) => (update.sourceId || entry.sourceId) === message.id).map((update) => `<button class="message-bubble assistant-bubble home-update" data-action="open" data-session="${escapeHTML(entry.sessionId || "")}" ${entry.sessionId ? "" : "disabled"}><span class="message-text markdown-content">${renderMarkdown(update.text)}</span></button>`).join("") || "";
    const pending = message.status === "routing" ? `<div class="home-progress"><i class="spinner"></i><span>Finding the right conversation…</span></div>` : entry?.status === "interrupted" && (entry.interruptedSourceId || entry.sourceId) === message.id ? `<div class="home-progress"><span>⏸️ Interrupted</span><button data-action="resume" data-entry="${escapeHTML(entry.id)}">Continue</button></div>` : "";
    return `<section class="home-exchange"><div class="message-row user-row home-requests">${request}</div>${pending}${updates ? `<div class="message-row assistant-row home-updates">${updates}</div>` : ""}</section>`;
  }).join("")}</div></main>`;
}
function sessionView() {
  const record = state.data.sessions.find((item) => item.id === state.selected);
  const messages = state.transcript.length ? state.transcript.map(renderMessage).join("") : `<div class="empty-session"><span class="brand-mark">✳</span><p>How can I help?</p></div>`;
  const queue = state.data.turns.filter((turn) => turn.sessionId === state.selected && turn.status === "queued");
  return `<main class="session-scroll scroll-area"><div class="transcript">${messages}${state.streaming ? renderMessage({ role: "assistant", text: state.streaming }) : ""}</div></main>${record?.status === "running" ? `<div class="activity-line"><i class="spinner"></i><span>${escapeHTML(state.activity || "Working")}</span></div>` : ""}${record?.status === "interrupted" ? `<div class="activity-line">⏸️ Interrupted on service restart. Return to Home to continue.</div>` : ""}${queue.length ? `<section class="queued-card"><h2>Queued follow-ups</h2>${queue.map((turn) => `<div class="queued-row"><span>${escapeHTML(turn.text)}</span></div>`).join("")}</section>` : ""}`;
}
function render() {
  const old = root.querySelector(".scroll-area");
  if (old) state.scroll[renderedView] = old.scrollTop;
  const focus = document.activeElement?.dataset?.focus;
  const cursor = focus ? document.activeElement.selectionStart : null;
  const isHome = state.selected === "home";
  const record = state.data.sessions.find((item) => item.id === state.selected);
  if (record?.status !== "running") state.steer = false;
  root.innerHTML = `<div class="app-shell"><header class="topbar"><div class="topbar-side">${isHome ? "" : `<button class="icon-button back-button" data-action="home" aria-label="Back to Home" title="Home">${icon("back", 19)}</button>`}</div><div class="brand">${isHome ? `<span class="brand-mark">${icon("sparkle", 14)}</span><strong>Assistant</strong>` : `<strong>${escapeHTML(record?.title || "Conversation")}</strong><span class="role-label">${escapeHTML(record?.role || "personal")}</span>`}</div><div class="topbar-side topbar-end"><span class="connection-dot ${state.connected ? "online" : ""}" title="${state.connected ? "Connected" : "Reconnecting"}"></span></div></header>${isHome ? home() : sessionView()}${state.error ? `<div class="connection-error"><span>${escapeHTML(state.error)}</span><button data-action="dismiss">Dismiss</button></div>` : ""}<footer class="composer-area"><form class="composer" id="composer"><textarea data-focus="composer" rows="1" placeholder="${isHome ? "Ask anything or give me a task" : "Message this conversation"}" aria-label="Message">${escapeHTML(state.input)}</textarea>${!isHome && record?.status === "running" ? `<button type="button" class="composer-icon steer-button ${state.steer ? "steer-selected" : ""}" data-action="toggle-steer" title="${state.steer ? "Steering after the current tool finishes; click to queue instead" : "Steer after the current tool finishes instead of queueing"}" aria-label="${state.steer ? "Steering active work" : "Steer active work"}" aria-pressed="${state.steer}">${state.steer ? "Steering" : "Steer"}</button><button type="button" class="composer-icon" data-action="stop" title="Stop current run" aria-label="Stop current run">${icon("stop", 17)}</button>` : ""}<button type="submit" class="send-button" aria-label="Send">${icon("send", 18)}</button></form>${state.steer ? `<div class="composer-hint">Steer: your message takes effect after the current tool call</div>` : ""}</footer></div>`;
  renderedView = state.selected;
  const scroll = root.querySelector(".scroll-area");
  if (scroll) scroll.scrollTop = state.scroll[state.selected] ?? scroll.scrollHeight;
  const input = focus ? root.querySelector('[data-focus="composer"]') : null;
  if (input) { input.focus({ preventScroll: true }); if (cursor !== null) input.setSelectionRange(cursor, cursor); }
}
async function loadSession() {
  if (state.selected === "home") return;
  const selected = state.selected;
  try {
    const result = await api(`/api/sessions/${encodeURIComponent(selected)}`);
    if (selected !== state.selected) return;
    state.transcript = result.messages;
    state.streaming = "";
    render();
  } catch (error) { state.error = error.message; render(); }
}
function select(id) {
  if (!id || id === state.selected) return;
  state.sessionDrafts[state.selected] = state.input;
  state.selected = id;
  localStorage.setItem("assistant-view", id);
  state.input = state.sessionDrafts[id] || "";
  state.steer = false;
  state.error = "";
  state.transcript = [];
  state.streaming = "";
  render();
  void loadSession();
}
root.addEventListener("click", async (event) => {
  const button = event.target.closest("[data-action]");
  if (!button) return;
  try {
    if (button.dataset.action === "open") select(button.dataset.session);
    if (button.dataset.action === "home") select("home");
    if (button.dataset.action === "dismiss") { state.error = ""; render(); }
    if (button.dataset.action === "toggle-steer") { state.steer = !state.steer; render(); }
    if (button.dataset.action === "stop") await api("/api/stop", "POST", { sessionId: state.selected });
    if (button.dataset.action === "resume") await api("/api/resume", "POST", { entryId: button.dataset.entry });
  } catch (error) { state.error = error.message; render(); }
});
root.addEventListener("input", (event) => {
  if (event.target.matches('[data-focus="composer"]')) {
    state.input = event.target.value;
    event.target.style.height = "38px";
    event.target.style.height = `${Math.min(event.target.scrollHeight, 144)}px`;
  }
});
root.addEventListener("keydown", (event) => {
  if (event.target.matches('[data-focus="composer"]') && event.key === "Enter" && !event.shiftKey) {
    event.preventDefault();
    root.querySelector("#composer").requestSubmit();
  }
});
root.addEventListener("submit", async (event) => {
  if (event.target.id !== "composer") return;
  event.preventDefault();
  const text = state.input.trim();
  if (!text) return;
  const selected = state.selected;
  state.input = "";
  state.error = "";
  if (selected === "home") {
    const id = crypto.randomUUID();
    state.data.messages.push({ id, text, createdAt: new Date().toISOString(), entryId: null, status: "routing" });
    render();
    try { await api("/api/home", "POST", { id, text }); }
    catch (error) { state.error = error.message; state.input = text; state.data.messages = state.data.messages.filter((item) => item.id !== id); render(); }
  } else {
    try { await api("/api/turns", "POST", { sessionId: selected, text, mode: state.steer ? "steer" : "followUp" }); state.steer = false; await loadSession(); }
    catch (error) { state.error = error.message; state.input = text; render(); }
  }
});

function connect() {
  const stream = new EventSource("/api/events");
  stream.onopen = () => { state.connected = true; render(); };
  stream.onerror = () => { state.connected = false; render(); };
  stream.onmessage = ({ data }) => {
    const event = JSON.parse(data);
    if (event.type === "snapshot") { state.data = event.data; render(); if (state.selected !== "home") void loadSession(); }
    if (event.type === "delta" && event.sessionId === state.selected) { state.streaming += event.delta; render(); }
    if (event.type === "activity" && event.sessionId === state.selected) { state.activity = `Using ${event.name}`; render(); }
  };
}
render();
connect();
