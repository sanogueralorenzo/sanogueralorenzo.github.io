import { escapeHTML, icon, renderMarkdown, renderMessage } from "./view.js";

const root = document.querySelector("#app");
const restoredDraft = sessionStorage.getItem("assistant-reload-draft") || "";
const restoredReply = sessionStorage.getItem("assistant-reload-reply");
const restoredEdit = JSON.parse(sessionStorage.getItem("assistant-reload-edit") || "null");
sessionStorage.removeItem("assistant-reload-draft");
sessionStorage.removeItem("assistant-reload-reply");
sessionStorage.removeItem("assistant-reload-edit");
const state = { data: { messages: [], entries: [], sessions: [], turns: [] }, selected: localStorage.getItem("assistant-view") || "home",
  transcript: [], input: restoredDraft, replyToId: restoredReply, edit: restoredEdit, sessionDrafts: {}, scroll: { home: 0 }, error: "", connected: false, streaming: "", activity: "", liveProgress: {}, steer: false, unseenReplies: new Map(), snapshotLoaded: false };
let renderedView = state.selected;
const pendingThumbs = new Set();

async function api(path, method = "GET", body) {
  const response = await fetch(path, { method, headers: body ? { "content-type": "application/json" } : {}, body: body ? JSON.stringify(body) : undefined });
  const result = await response.json();
  if (!response.ok) throw new Error(result.error || `Request failed (${response.status})`);
  return result;
}
function replyTarget(id) {
  if (!id) return null;
  const message = state.data.messages.find((item) => item.id === id);
  if (message) return { role: "You", text: message.text, sessionId: state.data.entries.find((entry) => entry.id === message.entryId)?.sessionId };
  for (const entry of state.data.entries) {
    const update = entry.updates.find((item) => item.id === id);
    if (update) return { role: "Assistant", text: update.text, sessionId: entry.sessionId };
  }
  const reply = state.transcript.find((message) => message.id === id && message.role === "assistant");
  if (reply) return { role: "Assistant", text: reply.text, sessionId: state.selected };
  return null;
}
function quote(target, className) {
  if (!target) return "";
  const text = target.text.replace(/\s+/g, " ").trim();
  const preview = text.length > 80 ? `${text.slice(0, 80).trimEnd()}…` : text;
  return `<span class="${className}"><strong>${target.role}</strong><span>${escapeHTML(preview)}</span></span>`;
}
function replyButton(id, sessionId) {
  return sessionId ? `<button type="button" class="reply-action" data-action="reply" data-reply="${escapeHTML(id)}" aria-label="Reply to message" title="Reply">${icon("reply", 14)}</button>` : "";
}
function thumbsUpButton(id, sessionId) {
  if (!id || !sessionId) return "";
  const pending = pendingThumbs.has(id);
  const sent = !!reactionTo(id) && !pending;
  const label = pending ? "Sending…" : sent ? "Go ahead sent" : "Go ahead";
  return `<button type="button" class="reply-action thumbs-up-action ${pending ? "pending" : sent ? "sent" : ""}" ${sent ? 'aria-disabled="true"' : 'data-action="thumbs-up"'} data-reply="${escapeHTML(id)}" data-session="${escapeHTML(sessionId)}" aria-label="${label}" title="${label}" ${pending ? "disabled" : ""}>${icon("thumbs-up", 14)}</button>`;
}
function reactionTo(id) {
  return state.data.messages.find((message) => message.replyToId === id && message.reaction === "thumbs-up");
}
function messageAction(message, sessionId) {
  const active = state.data.turns.some((turn) => turn.sourceId === message.id && turn.status === "running");
  return active ? `<button type="button" class="reply-action" data-action="edit" data-edit="${escapeHTML(message.id)}" aria-label="Edit active message" title="Edit and steer">${icon("edit", 14)}</button>` : replyButton(message.id, sessionId);
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
function activityPill(message, entry, className = "") {
  const progress = state.liveProgress[message.id] ?? entry?.updates.filter((update) => update.kind === "progress" && (update.sourceId || entry.sourceId) === message.id).at(-1)?.text;
  const status = messageStatus(message, entry);
  const title = entry?.sessionId ? entry.title : status === "failed" ? "Routing failed" : "Choosing a conversation…";
  const detail = ({ routing: "", queued: "Queued", working: progress?.replace(/\s+/g, " ").trim() || "Working…",
    ready: "Open conversation", failed: entry?.sessionId ? "Failed · Open conversation" : "", interrupted: "Continue" })[status] || "";
  const symbol = ["routing", "queued", "working"].includes(status) ? '<i class="spinner"></i>'
    : status === "ready" ? icon("check", 14) : status === "interrupted" ? "⏸" : "⚠";
  const action = status === "interrupted" && entry?.sessionId ? `data-action="resume" data-entry="${escapeHTML(entry.id)}"`
    : entry?.sessionId ? `data-action="open" data-session="${escapeHTML(entry.sessionId)}"` : "disabled";
  return `<button type="button" class="activity-pill ${className}" data-source="${escapeHTML(message.id)}" data-status="${escapeHTML(status)}" ${action}
    aria-label="${escapeHTML(`${title}${detail ? `, ${detail}` : ""}`)}" title="${escapeHTML(title)}"><span class="pill-symbol" aria-hidden="true">${symbol}</span><strong class="pill-title">${escapeHTML(title)}</strong>${detail ? `<span class="pill-detail">${escapeHTML(detail)}</span>` : ""}</button>`;
}
function homeRequest(message, entry) {
  const request = `<button type="button" class="message-bubble user-bubble home-entry" ${entry?.sessionId ? `data-action="open" data-session="${escapeHTML(entry.sessionId)}"` : "disabled"}>${quote(replyTarget(message.replyToId), "message-context user-context")}<span class="entry-copy">${escapeHTML(message.text)}</span></button>`;
  return `<section class="home-exchange"><div class="message-row user-row home-requests"><div class="replyable replyable-user">${messageAction(message, entry?.sessionId)}${request}</div>${activityPill(message, entry)}</div></section>`;
}
function homeReply(update, entry, source) {
  const reaction = reactionTo(update.id);
  const sourcePill = reaction ? activityPill(reaction, entry, "reply-source-pill") : entry.sessionId ? `<button type="button" class="activity-pill reply-source-pill" data-action="open" data-session="${escapeHTML(entry.sessionId)}" aria-label="Open ${escapeHTML(entry.title)} conversation" title="Open conversation"><span class="pill-symbol" aria-hidden="true">${icon("reply", 14)}</span><strong class="pill-title">${escapeHTML(entry.title)}</strong></button>` : "";
  const context = source.reaction ? replyTarget(source.replyToId) : { role: "You", text: source.text };
  return `<section class="home-exchange" data-update="${escapeHTML(update.id)}"><div class="message-row assistant-row home-updates"><div class="replyable replyable-assistant"><div class="message-actions">${thumbsUpButton(update.id, entry.sessionId)}${replyButton(update.id, entry.sessionId)}</div><button class="message-bubble assistant-bubble home-update ${update.quoteSource ? "with-context" : ""}" data-action="open" data-session="${escapeHTML(entry.sessionId || "")}" ${entry.sessionId ? "" : "disabled"}>${update.quoteSource ? quote(context, "message-context") : ""}<span class="message-text markdown-content">${renderMarkdown(update.text)}</span></button></div>${sourcePill}</div></section>`;
}
function home() {
  if (!state.data.messages.length) return `<main class="home-scroll scroll-area"><div class="home-content"><div class="empty-home-chat"><span class="brand-mark">${icon("sparkle", 17)}</span><strong>How can I help?</strong><p>Ask me anything or give me a task.</p></div></div></main>`;
  const edited = new Set(state.data.messages.map((message) => message.editOfId).filter(Boolean));
  const messages = new Map(state.data.messages.map((message) => [message.id, message]));
  const entries = new Map(state.data.entries.map((entry) => [entry.id, entry]));
  const timeline = state.data.messages.filter((message) => !message.reaction && !edited.has(message.id)).map((message) => ({ createdAt: message.createdAt, html: homeRequest(message, entries.get(message.entryId)) }));
  for (const entry of state.data.entries) for (const update of entry.updates) {
    if (update.kind === "progress") continue;
    const source = messages.get(update.sourceId || entry.sourceId);
    if (source && !edited.has(source.id)) timeline.push({ createdAt: update.createdAt, html: homeReply(update, entry, source) });
  }
  timeline.sort((a, b) => a.createdAt.localeCompare(b.createdAt));
  return `<main class="home-scroll scroll-area"><div class="home-content">${timeline.map((item) => item.html).join("")}</div></main>`;
}
function nearBottom(scroll) { return scroll.scrollHeight - scroll.scrollTop - scroll.clientHeight < 40; }
function homeBackButton() {
  const unread = [...state.unseenReplies.values()].some((sessionId) => sessionId !== state.selected);
  return `<button class="icon-button back-button ${unread ? "has-unread" : ""}" data-action="home" aria-label="${unread ? "Back to Home, new replies" : "Back to Home"}" title="${unread ? "Home · new replies" : "Home"}">${icon("back", 19)}</button>`;
}
function sessionView() {
  const record = state.data.sessions.find((item) => item.id === state.selected);
  const messages = state.transcript.length ? state.transcript.filter((message) => !message.reaction).map((message) => renderMessage(message,
    message.role === "assistant" && message.replyable ? `<div class="message-actions">${thumbsUpButton(message.id, state.selected)}</div>` : "")).join("") : `<div class="empty-session"><span class="brand-mark">✳</span><p>How can I help?</p></div>`;
  const queue = state.data.turns.filter((turn) => turn.sessionId === state.selected && turn.status === "queued");
  return `<main class="session-scroll scroll-area"><div class="transcript">${messages}${state.streaming ? renderMessage({ role: "assistant", text: state.streaming }) : ""}</div></main>${record?.status === "running" ? `<div class="activity-line"><i class="spinner"></i><span>${escapeHTML(state.activity || "Working")}</span></div>` : ""}${record?.status === "interrupted" ? `<div class="activity-line">⏸️ Interrupted on service restart. Return to Home to continue.</div>` : ""}${queue.length ? `<section class="queued-card"><h2>Queued follow-ups</h2>${queue.map((turn) => `<div class="queued-row"><span>${state.data.messages.find((message) => message.id === turn.sourceId)?.reaction ? "👍 Go ahead" : escapeHTML(turn.text)}</span></div>`).join("")}</section>` : ""}`;
}
function render(force = false) {
  const old = root.querySelector(".scroll-area");
  if (!force && state.selected === "home" && renderedView === "home" && old?.classList.contains("home-scroll") &&
    !state.error && !root.querySelector(".connection-error")) {
    const wasNearBottom = nearBottom(old);
    const scrollTop = old.scrollTop;
    const next = document.createElement("template");
    next.innerHTML = home();
    const current = old.querySelector(".home-content");
    const fresh = next.content.querySelector(".home-content");
    const children = [...fresh.children];
    for (let i = 0; i < children.length; i++) {
      const existing = current.children[i];
      const updated = children[i];
      if (!existing) current.append(updated);
      else if (!existing.isEqualNode(updated)) existing.replaceWith(updated);
    }
    while (current.children.length > children.length) current.lastElementChild.remove();
    old.scrollTop = wasNearBottom ? old.scrollHeight : scrollTop;
    updateConnection();
    return;
  }
  if (old) state.scroll[renderedView] = old.scrollTop;
  const focus = document.activeElement?.dataset?.focus;
  const cursor = focus ? document.activeElement.selectionStart : null;
  const isHome = state.selected === "home";
  const record = state.data.sessions.find((item) => item.id === state.selected);
  if (record?.status !== "running") state.steer = false;
  const editing = isHome && state.edit;
  const preview = editing ? replyTarget(state.edit.id) : isHome && state.replyToId ? replyTarget(state.replyToId) : null;
  const previewHTML = preview ? `<div class="reply-preview">${quote(editing ? { role: "Editing message", text: preview.text } : preview, "reply-preview-text")}<button type="button" class="dismiss-reply" data-action="${editing ? "dismiss-edit" : "dismiss-reply"}" aria-label="${editing ? "Cancel edit" : "Cancel reply"}" title="${editing ? "Cancel edit" : "Cancel reply"}">${icon("close", 16)}</button></div>` : "";
  root.innerHTML = `<div class="app-shell"><header class="topbar${isHome ? " home-topbar" : ""}"><div class="topbar-side">${isHome ? "" : homeBackButton()}</div><div class="brand"><strong>${isHome ? "Assistant" : escapeHTML(record?.title || "Conversation")}</strong></div><div class="topbar-side topbar-end"><span class="connection-dot ${state.connected ? "online" : ""}" title="${state.connected ? "Connected" : "Reconnecting"}"></span></div></header>${isHome ? home() : sessionView()}${state.error ? `<div class="connection-error"><span>${escapeHTML(state.error)}</span><button data-action="dismiss">Dismiss</button></div>` : ""}<footer class="composer-area"><form class="composer ${preview ? "replying" : ""}" id="composer">${previewHTML}<textarea data-focus="composer" rows="1" placeholder="Message" aria-label="Message">${escapeHTML(state.input)}</textarea>${!isHome && record?.status === "running" ? `<button type="button" class="composer-icon steer-button ${state.steer ? "steer-selected" : ""}" data-action="toggle-steer" title="${state.steer ? "Steering after the current tool finishes; click to queue instead" : "Steer after the current tool finishes instead of queueing"}" aria-label="${state.steer ? "Steering active work" : "Steer active work"}" aria-pressed="${state.steer}">${state.steer ? "Steering" : "Steer"}</button><button type="button" class="composer-icon" data-action="stop" title="Stop current run" aria-label="Stop current run">${icon("stop", 17)}</button>` : ""}<button type="submit" class="send-button" aria-label="Send">${icon("send", 18)}</button></form>${editing ? `<div class="composer-hint edit-hint">Sending this will steer the conversation</div>` : state.steer ? `<div class="composer-hint">Steer: your message takes effect after the current tool call</div>` : ""}</footer></div>`;
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
  const unread = id === "home" ? new Set(state.unseenReplies.keys()) : null;
  state.sessionDrafts[state.selected] = state.input;
  state.selected = id;
  localStorage.setItem("assistant-view", id);
  state.input = state.sessionDrafts[id] || "";
  state.steer = false;
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
    if (button.dataset.action === "thumbs-up") {
      const replyToId = button.dataset.reply;
      if (pendingThumbs.has(replyToId)) return;
      const sessionId = button.dataset.session;
      const id = crypto.randomUUID();
      const entry = state.data.entries.find((item) => item.updates.some((update) => update.id === replyToId))
        || [...state.data.entries].reverse().find((item) => item.sessionId === sessionId);
      pendingThumbs.add(replyToId);
      state.error = "";
      state.data.messages.push({ id, text: "Yes, go ahead.", createdAt: new Date().toISOString(), entryId: entry?.id || null, replyToId, reaction: "thumbs-up", status: "routed" });
      render();
      try {
        await api("/api/turns", "POST", { id, sessionId, text: "Yes, go ahead.", mode: "followUp", replyToId, reaction: "thumbs-up" });
      } catch (error) {
        state.data.messages = state.data.messages.filter((message) => message.id !== id);
        throw error;
      } finally {
        pendingThumbs.delete(replyToId);
        render();
      }
    }
    if (button.dataset.action === "open") select(button.dataset.session);
    if (button.dataset.action === "home") select("home");
    if (button.dataset.action === "reply") {
      const target = replyTarget(button.dataset.reply);
      if (target?.sessionId) {
        state.input = root.querySelector("textarea")?.value || "";
        state.edit = null;
        state.replyToId = button.dataset.reply;
        render(true);
        root.querySelector("textarea")?.focus();
      }
    }
    if (button.dataset.action === "edit") {
      const message = state.data.messages.find((item) => item.id === button.dataset.edit);
      if (message && state.data.turns.some((turn) => turn.sourceId === message.id && turn.status === "running")) {
        state.edit = { id: message.id, previousInput: root.querySelector("textarea")?.value || "", previousReplyToId: state.replyToId };
        state.replyToId = null;
        state.input = message.text;
        render(true);
        root.querySelector("textarea")?.focus();
      }
    }
    if (button.dataset.action === "dismiss-reply") {
      state.input = root.querySelector("textarea")?.value || "";
      state.replyToId = null;
      render(true);
      root.querySelector("textarea")?.focus();
    }
    if (button.dataset.action === "dismiss-edit") {
      state.input = state.edit?.previousInput || "";
      state.replyToId = state.edit?.previousReplyToId || null;
      state.edit = null;
      render(true);
      root.querySelector("textarea")?.focus();
    }
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
  const composer = event.target.querySelector("textarea");
  const text = composer.value.trim();
  if (!text) return;
  const selected = state.selected;
  const edit = selected === "home" ? state.edit : null;
  const editOfId = edit?.id || null;
  const replyToId = selected === "home" && !edit ? state.replyToId : null;
  const target = replyToId || editOfId ? replyTarget(replyToId || editOfId) : null;
  if ((replyToId || editOfId) && !target?.sessionId) { state.error = "This message is not in a conversation yet"; render(true); return; }
  if (editOfId && text === target.text) { state.error = "Change the message before sending a revision"; render(true); return; }
  if (editOfId && !state.data.turns.some((turn) => turn.sourceId === editOfId && turn.status === "running")) {
    state.error = "This turn has finished. Cancel the edit and use Reply for a follow-up.";
    render(true);
    return;
  }
  state.input = edit?.previousInput || "";
  composer.value = "";
  state.error = "";
  if (selected === "home") {
    const id = crypto.randomUUID();
    state.replyToId = edit?.previousReplyToId || null;
    state.edit = null;
    state.data.messages.push({ id, text, createdAt: new Date().toISOString(), entryId: null, replyToId, editOfId, status: replyToId || editOfId ? "routed" : "routing" });
    render(!!(replyToId || editOfId));
    try {
      if (editOfId) await api("/api/turns", "POST", { id, sessionId: target.sessionId, text, mode: "steer", editOfId });
      else if (replyToId) await api("/api/turns", "POST", { id, sessionId: target.sessionId, text, mode: "followUp", replyToId });
      else await api("/api/home", "POST", { id, text });
    } catch (error) {
      state.error = error.message;
      state.input = text;
      state.replyToId = replyToId;
      state.edit = edit;
      state.data.messages = state.data.messages.filter((item) => item.id !== id);
      render(true);
    }
  } else {
    try { await api("/api/turns", "POST", { sessionId: selected, text, mode: state.steer ? "steer" : "followUp" }); state.steer = false; await loadSession(); }
    catch (error) { state.error = error.message; state.input = text; render(); }
  }
});

function connect() {
  const stream = new EventSource("/api/events");
  let opened = false;
  stream.onopen = () => {
    if (opened) {
      sessionStorage.setItem("assistant-reload-draft", root.querySelector("textarea")?.value || "");
      if (state.replyToId) sessionStorage.setItem("assistant-reload-reply", state.replyToId);
      if (state.edit) sessionStorage.setItem("assistant-reload-edit", JSON.stringify(state.edit));
      location.reload();
      return;
    }
    opened = true;
    state.connected = true;
    updateConnection();
  };
  stream.onerror = () => { state.connected = false; updateConnection(); };
  stream.onmessage = ({ data }) => {
    const event = JSON.parse(data);
    if (event.type === "snapshot") {
      const previous = new Set(state.data.entries.flatMap((entry) => entry.updates.filter((update) => update.kind !== "progress").map((update) => update.id)));
      state.data = event.data;
      if (state.selected !== "home" && !state.data.sessions.some((session) => session.id === state.selected)) {
        state.selected = "home";
        localStorage.setItem("assistant-view", "home");
        state.transcript = [];
      }
      if (state.replyToId && !replyTarget(state.replyToId)) state.replyToId = null;
      if (state.edit && !replyTarget(state.edit.id)) state.edit = null;
      if (state.snapshotLoaded) for (const entry of state.data.entries) for (const update of entry.updates) {
        if (update.kind !== "progress" && !previous.has(update.id) && state.selected !== "home" && entry.sessionId !== state.selected)
          state.unseenReplies.set(update.id, entry.sessionId);
      }
      state.snapshotLoaded = true;
      render(!!(state.replyToId || state.edit) && !root.querySelector(".reply-preview"));
      if (state.selected !== "home") void loadSession();
    }
    if (event.type === "delta" && event.sessionId === state.selected) { state.streaming += event.delta; render(); }
    if (event.type === "activity" && event.sessionId === state.selected) { state.activity = event.label; render(); }
    if (event.type === "homeActivity") {
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
  const dot = root.querySelector(".connection-dot");
  if (!dot) return;
  dot.classList.toggle("online", state.connected);
  dot.title = state.connected ? "Connected" : "Reconnecting";
}
render();
connect();
