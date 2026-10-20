import { escapeHTML, icon, renderMarkdown, renderMessage } from "./view.js";
import { createMessageActions } from "./message-actions.js";
import { createComposer } from "./composer.js";
import { createQueuedMessages } from "./queued-messages.js";
import { createProviders } from "./providers.js";
import { createLanding } from "./landing.js";

const root = document.querySelector("#app");
const state = { data: { messages: [], entries: [], sessions: [], turns: [] }, selected: localStorage.getItem("assistant-view") || "home",
  transcript: [], sessionRevision: 0, scroll: { home: 0 }, error: "", connected: false, streaming: "", liveProgress: {}, unseenReplies: new Map(), snapshotLoaded: false };
let renderedView = state.selected;
let renderedContent;
root.innerHTML = `<div class="app-shell"><header class="topbar"><div class="topbar-side"></div><div class="brand"><strong></strong></div><div class="topbar-side topbar-end"></div></header><div class="conversation-content"></div><div class="connection-error" hidden><span></span><button data-action="dismiss">Dismiss</button></div></div>`;
const actions = createMessageActions({ state, api, render });
const composer = createComposer({ state, api, render, loadSession, actions });
const queued = createQueuedMessages({ state, api, render, composer });
root.querySelector(".app-shell").append(composer.element);
const landing = createLanding({ root, composer });
const providers = createProviders({ state, root, api });
root.querySelector(".topbar-end").innerHTML = providers.html();

async function api(path, method = "GET", body) {
  const response = await fetch(path, { method, headers: body ? { "content-type": "application/json" } : {}, body: body ? JSON.stringify(body) : undefined });
  const result = await response.json();
  if (!response.ok) throw new Error(result.error || `Request failed (${response.status})`);
  return result;
}
function messageStatus(message, entry) {
  const turn = state.data.turns.find((item) => item.sourceId === message.id);
  if (turn) return turn.status === "running" ? "working" : "queued";
  if (entry?.status === "interrupted" && (entry.interruptedSourceId || entry.sourceId) === message.id) return "interrupted";
  const latest = entry?.updates.filter((item) => (item.sourceId || entry.sourceId) === message.id).at(-1);
  if (latest?.kind === "result") return "ready";
  if (latest?.kind === "error") return "failed";
  if (latest) return "working";
  return message.status === "routed" ? "queued" : message.status;
}
function activityPill(message, entry, className = "", showConversation = true) {
  if (!entry?.sessionId) return "";
  const progress = state.liveProgress[message.id];
  const status = messageStatus(message, entry);
  const title = entry.title;
  const detail = ({ queued: "Queued", working: progress?.replace(/\s+/g, " ").trim() || "Working…",
    ready: "", failed: "Failed", interrupted: "Continue" })[status] || "";
  if (!showConversation && status === "ready") return "";
  const symbol = ["queued", "working"].includes(status) ? '<i class="spinner"></i>'
    : status === "ready" ? icon("check", 14) : status === "interrupted" ? "⏸" : "⚠";
  const action = status === "interrupted" ? `data-action="resume" data-entry="${escapeHTML(entry.id)}"`
    : `data-action="open" data-session="${escapeHTML(entry.sessionId)}"`;
  return `<button type="button" class="activity-pill ${className}" data-source="${escapeHTML(message.id)}" data-status="${escapeHTML(status)}" ${action}
    aria-label="${escapeHTML(`${title}${detail ? `, ${detail}` : ""}`)}" title="${escapeHTML(title)}"><span class="pill-symbol" aria-hidden="true">${symbol}</span>${showConversation ? `<strong class="pill-title">${escapeHTML(title)}</strong>` : ""}${detail ? `<span class="pill-detail">${escapeHTML(detail)}</span>` : ""}</button>`;
}
function homeRequest(message, entry, showConversation) {
  const turn = state.data.turns.find((item) => item.sourceId === message.id && item.status === "queued");
  const request = `<button type="button" class="message-bubble user-bubble home-entry" ${entry?.sessionId ? `data-action="open" data-session="${escapeHTML(entry.sessionId)}"` : "disabled"}>${actions.quote(actions.replyTarget(message.replyToId), "message-context user-context")}<span class="entry-copy">${escapeHTML(message.text)}</span></button>`;
  return `<section class="home-exchange"><div class="message-row user-row home-requests"><div class="replyable replyable-user">${turn ? queued.controls(turn, true) : actions.requestAction(message, entry?.sessionId)}${request}</div>${activityPill(message, entry, "", showConversation)}</div></section>`;
}
function homeReply(update, entry, source, showConversation) {
  const reaction = actions.reactionTo(update.id);
  const sourcePill = reaction ? activityPill(reaction, entry, "reply-source-pill", showConversation) : showConversation && entry.sessionId ? `<button type="button" class="activity-pill reply-source-pill" data-action="open" data-session="${escapeHTML(entry.sessionId)}" aria-label="Open ${escapeHTML(entry.title)} conversation" title="${escapeHTML(entry.title)}"><span class="pill-symbol" aria-hidden="true">${icon("reply", 14)}</span><strong class="pill-title">${escapeHTML(entry.title)}</strong></button>` : "";
  const context = source.reaction ? actions.replyTarget(source.replyToId) : { role: "You", text: source.text };
  return `<section class="home-exchange" data-update="${escapeHTML(update.id)}"><div class="message-row assistant-row home-updates"><div class="replyable replyable-assistant">${actions.replyActions(update.id, entry.sessionId)}<button class="message-bubble assistant-bubble home-update ${update.quoteSource ? "with-context" : ""}" data-action="open" data-session="${escapeHTML(entry.sessionId || "")}" ${entry.sessionId ? "" : "disabled"}>${update.quoteSource ? actions.quote(context, "message-context") : ""}<span class="message-text markdown-content">${renderMarkdown(update.text)}</span></button></div>${sourcePill}</div></section>`;
}
function home() {
  if (!state.data.messages.length) return landing.view();
  const edited = new Set(state.data.messages.map((message) => message.editOfId).filter(Boolean));
  const messages = new Map(state.data.messages.map((message) => [message.id, message]));
  const entries = new Map(state.data.entries.map((entry) => [entry.id, entry]));
  const timeline = state.data.messages.filter((message) => !message.reaction && !edited.has(message.id)).map((message) => {
    const entry = entries.get(message.entryId);
    return { createdAt: message.createdAt, sessionId: entry?.sessionId, render: (showConversation) => homeRequest(message, entry, showConversation) };
  });
  for (const entry of state.data.entries) for (const update of entry.updates) {
    if (update.kind === "progress") continue;
    const source = messages.get(update.sourceId || entry.sourceId);
    if (source && !edited.has(source.id)) timeline.push({ createdAt: update.createdAt, sessionId: entry.sessionId, render: (showConversation) => homeReply(update, entry, source, showConversation) });
  }
  timeline.sort((a, b) => a.createdAt.localeCompare(b.createdAt));
  let previousSession;
  const content = timeline.map((item) => {
    const showConversation = item.sessionId && item.sessionId !== previousSession;
    if (item.sessionId) previousSession = item.sessionId;
    return item.render(showConversation);
  }).join("");
  return `<main class="home-scroll scroll-area"><div class="home-content">${content}</div></main>`;
}
function nearBottom(scroll) { return scroll.scrollHeight - scroll.scrollTop - scroll.clientHeight < 40; }
function homeBackButton() {
  const unread = [...state.unseenReplies.values()].some((sessionId) => sessionId !== state.selected);
  return `<button class="icon-button back-button ${unread ? "has-unread" : ""}" data-action="home" aria-label="${unread ? "Back to Home, new replies" : "Back to Home"}" title="${unread ? "Home · new replies" : "Home"}">${icon("back", 19)}</button>`;
}
function sessionView() {
  const record = state.data.sessions.find((item) => item.id === state.selected);
  const messages = state.transcript.length ? state.transcript.filter((message) => !message.reaction).map((message) => renderMessage(message,
    message.role === "assistant" && message.replyable ? actions.replyActions(message.id, state.selected) : "")).join("") : `<div class="empty-session"><span class="brand-mark">✳</span><p>How can I help?</p></div>`;
  return `<main class="session-scroll scroll-area"><div class="transcript">${messages}${state.streaming ? renderMessage({ role: "assistant", text: state.streaming }) : ""}</div></main>${record?.status === "running" ? `<div class="activity-line"><i class="spinner"></i><span>Working…</span></div>` : ""}${record?.status === "interrupted" ? `<div class="activity-line">⏸️ Stopped. Return to Home to continue.</div>` : ""}`;
}
function render() {
  const old = root.querySelector(".scroll-area");
  const sameView = state.selected === renderedView;
  const scrollTop = old?.scrollTop;
  const follow = !old || (sameView && nearBottom(old));
  if (old) state.scroll[renderedView] = old.scrollTop;
  const isHome = state.selected === "home";
  const record = state.data.sessions.find((item) => item.id === state.selected);
  const isLanding = isHome && !state.data.messages.length;
  root.querySelector(".app-shell").classList.toggle("is-landing", isLanding);
  landing.sync(isLanding);
  const topbar = root.querySelector(".topbar");
  topbar.classList.toggle("home-topbar", isHome);
  topbar.querySelector(".brand strong").textContent = isHome ? "Assistant" : record?.title || "Conversation";
  const back = isHome ? "" : homeBackButton();
  const side = topbar.querySelector(".topbar-side");
  if (side.innerHTML !== back) side.innerHTML = back;
  const html = isHome ? home() : sessionView();
  if (html !== renderedContent) {
    root.querySelector(".conversation-content").innerHTML = html;
    renderedContent = html;
  }
  const scroll = root.querySelector(".scroll-area");
  if (scroll) scroll.scrollTop = follow ? scroll.scrollHeight : sameView ? scrollTop : state.scroll[state.selected] ?? scroll.scrollHeight;
  renderedView = state.selected;
  const error = root.querySelector(".connection-error");
  error.hidden = !state.error;
  error.querySelector("span").textContent = state.error;
  updateConnection();
}
async function loadSession() {
  if (state.selected === "home") return;
  const selected = state.selected;
  const revision = state.sessionRevision;
  try {
    const result = await api(`/api/sessions/${encodeURIComponent(selected)}`);
    if (selected !== state.selected || revision !== state.sessionRevision) return;
    state.transcript = result.messages;
    state.streaming = result.streaming || "";
    render();
  } catch (error) { state.error = error.message; render(); }
}
function select(id) {
  if (!id || id === state.selected) return;
  const unread = id === "home" ? new Set(state.unseenReplies.keys()) : null;
  composer.selectView(id);
  localStorage.setItem("assistant-view", id);
  state.error = "";
  state.transcript = [];
  state.streaming = "";
  render();
  if (unread?.size) {
    const scroll = root.querySelector(".home-scroll");
    const first = [...root.querySelectorAll(".home-exchange[data-update]")].find((item) => unread.has(item.dataset.update));
    if (scroll && first) scroll.scrollTop += first.getBoundingClientRect().top - scroll.getBoundingClientRect().top - 28;
    state.unseenReplies.clear();
  }
  void loadSession();
}
root.addEventListener("click", async (event) => {
  const button = event.target.closest("[data-action]");
  if (!button || button.disabled) return;
  try {
    if (landing.handleClick(button)) return;
    if (await providers.handleClick(button)) return;
    if (await queued.handleClick(button)) return;
    if (composer.handleClick(button)) return;
    if (await actions.handleClick(button)) return;
    if (button.dataset.action === "open") select(button.dataset.session);
    if (button.dataset.action === "home") select("home");
    if (button.dataset.action === "dismiss") { state.error = ""; render(); }
    if (button.dataset.action === "stop") await api("/api/stop", "POST", { sessionId: state.selected });
    if (button.dataset.action === "resume") await api("/api/resume", "POST", { entryId: button.dataset.entry });
  } catch (error) { state.error = error.message; render(); }
});
function connect() {
  const stream = new EventSource("/api/events");
  stream.onopen = () => { state.connected = true; updateConnection(); };
  stream.onerror = () => { state.connected = false; updateConnection(); };
  stream.onmessage = ({ data }) => {
    const event = JSON.parse(data);
    if (event.type === "snapshot") {
      const previous = new Set(state.data.entries.flatMap((entry) => entry.updates.filter((update) => update.kind !== "progress").map((update) => update.id)));
      state.data = event.data;
      if (state.selected !== "home" && !state.data.sessions.some((session) => session.id === state.selected)) {
        composer.selectView("home");
        localStorage.setItem("assistant-view", "home");
        state.transcript = [];
      }
      composer.reconcile();
      if (state.snapshotLoaded) for (const entry of state.data.entries) for (const update of entry.updates) {
        if (update.kind !== "progress" && !previous.has(update.id) && state.selected !== "home" && entry.sessionId !== state.selected)
          state.unseenReplies.set(update.id, entry.sessionId);
      }
      state.snapshotLoaded = true;
      render();
    }
    if (event.type === "providers") providers.update(event.data);
    if (event.type === "conversation" && event.sessionId === state.selected) {
      state.sessionRevision++;
      state.transcript = event.messages;
      state.streaming = event.streaming;
      render();
    }
    if (event.type === "progress") {
      state.liveProgress[event.sourceId] = event.text;
      if (state.selected === "home") {
        const pill = [...root.querySelectorAll(".activity-pill")].find((item) => item.dataset.source === event.sourceId);
        if (pill?.dataset.status === "working") {
          const detail = pill.querySelector(".pill-detail");
          if (detail) detail.textContent = event.text.replace(/\s+/g, " ").trim() || "Working…";
          pill.setAttribute("aria-label", `${pill.querySelector(".pill-title")?.textContent}, ${detail?.textContent}`);
        }
      }
    }
  };
}
function updateConnection() {
  providers.sync();
  composer.sync(state.selected === "home" ? "" : queued.html());
}
render();
connect();
