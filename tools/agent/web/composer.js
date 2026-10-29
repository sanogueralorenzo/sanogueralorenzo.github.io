import { icon, renderQuote } from "./view.js";

const emptyDraft = () => ({ input: "", replyToId: null, edit: null, queuedEdit: null });
const storageKey = "agent-composer-drafts";

function suggestionTarget(state, draft) {
  if (!state.connected || draft.queuedEdit || draft.edit) return null;
  let target;
  if (state.selected === "home") {
    if (state.data.turns.length || state.data.messages.some((message) => message.status === "routing")) return null;
    const last = state.data.entries.flatMap((entry) => entry.updates.filter((update) => update.kind !== "progress")
      .map((update) => ({ sessionId: entry.sessionId, replyId: update.id, createdAt: update.createdAt, kind: update.kind })))
      .sort((a, b) => a.createdAt.localeCompare(b.createdAt)).at(-1);
    if (last?.kind !== "result" || state.data.messages.some((message) => message.createdAt > last.createdAt)) return null;
    target = { sessionId: last.sessionId, replyId: last.replyId };
  } else {
    const last = state.transcript.at(-1);
    if (!last?.completed) return null;
    target = { sessionId: state.selected, replyId: last.id };
  }
  const record = state.data.sessions.find((session) => session.id === target.sessionId);
  if (record?.status !== "idle" || state.data.turns.some((turn) => turn.sessionId === target.sessionId)) return null;
  return draft.replyToId && draft.replyToId !== target.replyId ? null : target;
}

export function createComposer({ state, api, render, loadSession, actions }) {
  const drafts = JSON.parse(sessionStorage.getItem(storageKey) || "{}");
  let draft = drafts[state.selected] || emptyDraft();
  let revision = 0;
  const suggestions = new Map();
  const dismissed = new Map();
  const lastShown = new Map();
  const element = document.createElement("footer");
  element.className = "composer-area";
  element.innerHTML = `<form class="composer" id="composer"><div class="composer-queue" hidden></div><div class="reply-preview" hidden></div><div class="composer-input"><textarea rows="1" placeholder="Message" aria-label="Message"></textarea><div class="prompt-suggestion" hidden><span></span></div></div><div class="composer-controls"><button type="button" class="composer-icon suggestion-action" data-action="accept-suggestion" title="Use suggested reply" aria-label="Use suggested reply" hidden><kbd>Tab</kbd></button><button type="button" class="composer-icon mic-button" title="Microphone — coming soon" aria-label="Microphone (coming soon)" disabled>${icon("mic", 18)}</button><button type="button" class="composer-icon" data-action="stop" title="Stop current run" aria-label="Stop current run" hidden>${icon("stop", 17)}</button><button type="submit" class="send-button" aria-label="Send">${icon("send", 18)}</button></div><div class="composer-hint edit-hint" hidden>Sending this will steer the conversation</div></form>`;
  const form = element.querySelector("form");
  const input = element.querySelector("textarea");
  const preview = element.querySelector(".reply-preview");
  const overlay = element.querySelector(".prompt-suggestion");
  const suggestionButton = element.querySelector(".suggestion-action");

  function persist() {
    revision++;
    drafts[state.selected] = draft;
    sessionStorage.setItem(storageKey, JSON.stringify(drafts));
  }
  function focus(atEnd = false) {
    input.focus({ preventScroll: true });
    if (atEnd) input.setSelectionRange(input.value.length, input.value.length);
  }
  function resize() {
    input.style.height = "38px";
    input.style.height = `${Math.min(input.scrollHeight, 144)}px`;
  }
  function change(values, atEnd = false) {
    Object.assign(draft, values);
    persist();
    render();
    focus(atEnd);
  }
  function restore(value) {
    draft = { ...emptyDraft(), ...value };
    persist();
  }
  function selectView(id) {
    drafts[state.selected] = draft;
    draft = drafts[id] || emptyDraft();
    state.selected = id;
    persist();
  }
  function editQueued(view, turn, text) {
    const previous = view === state.selected ? { ...draft } : drafts[view] || emptyDraft();
    const next = { input: text, replyToId: turn.replyToId || null, edit: null,
      queuedEdit: { sessionId: turn.sessionId, text, previous } };
    if (view === state.selected) { restore(next); render(); focus(true); }
    else { drafts[view] = next; persist(); }
  }
  function reconcile() {
    if (draft.replyToId && (state.selected === "home" || state.transcript.length) && !actions.replyTarget(draft.replyToId)) {
      draft.replyToId = null;
      persist();
    }
    if (draft.edit && !actions.replyTarget(draft.edit.id)) { draft.edit = null; persist(); }
  }
  function available(restoreDismissed = false) {
    const target = suggestionTarget(state, draft);
    const cached = target && suggestions.get(target.sessionId);
    const dismissal = target && dismissed.get(target.sessionId);
    const hidden = dismissal?.replyId === target?.replyId && !(restoreDismissed && dismissal?.reason === "escape");
    return target && !draft.input && !hidden && cached?.replyId === target.replyId && cached.text
      ? { ...target, text: cached.text } : null;
  }
  function paintSuggestion() {
    const hint = available();
    overlay.hidden = suggestionButton.hidden = !hint;
    input.placeholder = hint ? "" : state.selected === "home" && !state.data.messages.length ? "What would you like to do?" : "Message";
    if (!hint) { input.removeAttribute("aria-description"); return; }
    lastShown.set(state.selected, hint.text);
    overlay.querySelector("span").textContent = hint.text;
    suggestionButton.setAttribute("aria-label", `Use suggested reply: ${hint.text}`);
    input.setAttribute("aria-description", `Suggested reply: ${hint.text}. Press Tab to use it.`);
  }
  function syncSuggestions() {
    const target = suggestionTarget(state, draft);
    const dismissal = target && dismissed.get(target.sessionId);
    if (dismissal?.reason === "draft" && !draft.input && !draft.replyToId && !draft.edit) dismissed.delete(target.sessionId);
    if (target && suggestions.get(target.sessionId)?.replyId !== target.replyId) {
      const value = { replyId: target.replyId, text: null };
      suggestions.set(target.sessionId, value);
      void api("/api/suggestions", "POST", target).then((result) => {
        value.text = typeof result.text === "string" ? result.text : null;
      }).catch(() => {}).finally(paintSuggestion);
    }
    paintSuggestion();
  }
  function dismissSuggestion(reason) {
    const target = suggestionTarget(state, draft);
    if (target) dismissed.set(target.sessionId, { replyId: target.replyId, reason });
    paintSuggestion();
  }
  function acceptSuggestion() {
    const hint = available(true);
    if (!hint) return false;
    dismissed.set(hint.sessionId, { replyId: hint.replyId, reason: "draft" });
    change({ input: hint.text, replyToId: hint.replyId }, true);
    return true;
  }
  function sync(queueHTML = "") {
    const isHome = state.selected === "home";
    const target = actions.replyTarget(draft.edit?.id || draft.replyToId) || (draft.queuedEdit && {
      role: state.data.sessions.find((session) => session.id === draft.queuedEdit.sessionId)?.title || "Conversation",
      text: draft.queuedEdit.text,
    });
    form.className = `composer${isHome ? "" : " session-composer"}${target ? " replying" : ""}`;
    preview.hidden = !target;
    if (target) {
      const editing = draft.edit || draft.queuedEdit;
      const action = draft.edit ? "dismiss-edit" : draft.queuedEdit ? "dismiss-queued-edit" : "dismiss-reply";
      const label = editing ? "Cancel edit" : "Cancel reply";
      const html = `${renderQuote(draft.edit ? { role: "Editing message", text: target.text } : target, "reply-preview-text")}<button type="button" class="dismiss-reply" data-action="${action}" aria-label="${label}" title="${label}">${icon("close", 16)}</button>`;
      if (preview.innerHTML !== html) preview.innerHTML = html;
    }
    const queue = element.querySelector(".composer-queue");
    queue.hidden = !queueHTML;
    if (queue.innerHTML !== queueHTML) queue.innerHTML = queueHTML;
    element.querySelector(".composer-hint").hidden = !draft.edit;
    element.querySelector('[data-action="stop"]').hidden = isHome || state.data.sessions.find((session) => session.id === state.selected)?.status !== "running";
    if (input.value !== draft.input) { input.value = draft.input; resize(); }
    syncSuggestions();
  }
  function handleClick(button) {
    switch (button.dataset.action) {
      case "accept-suggestion": acceptSuggestion(); return true;
      case "reply":
        if (actions.replyTarget(button.dataset.reply)?.sessionId)
          change({ edit: null, queuedEdit: null, replyToId: button.dataset.reply });
        return true;
      case "edit": {
        const message = state.data.messages.find((item) => item.id === button.dataset.edit);
        if (message && state.data.turns.some((turn) => turn.sourceId === message.id && turn.status === "running"))
          change({ edit: { id: message.id, previous: { ...draft } }, queuedEdit: null, replyToId: null, input: message.text }, true);
        return true;
      }
      case "dismiss-reply": change({ replyToId: null }); return true;
      case "dismiss-edit": restore(draft.edit?.previous); render(); focus(); return true;
      case "dismiss-queued-edit": restore(draft.queuedEdit?.previous); render(); focus(); return true;
      default: return false;
    }
  }
  function escape() {
    if (draft.edit) return handleClick({ dataset: { action: "dismiss-edit" } });
    if (draft.queuedEdit) return handleClick({ dataset: { action: "dismiss-queued-edit" } });
    const target = suggestionTarget(state, { ...draft, replyToId: null });
    const cached = target && suggestions.get(target.sessionId);
    const lastText = lastShown.get(state.selected) || (cached?.replyId === target?.replyId ? cached.text : null);
    const matches = !!lastText && draft.input === lastText;
    const quoted = !!draft.replyToId;
    if (matches || quoted) change({ input: matches ? "" : draft.input, replyToId: null });
    else if (!draft.input) dismissSuggestion("escape");
    return matches || quoted || !draft.input;
  }
  input.addEventListener("input", () => { draft.input = input.value; persist(); dismissSuggestion("draft"); resize(); });
  input.addEventListener("keydown", (event) => {
    if (event.isComposing) return;
    if (event.key === "Tab" && !event.shiftKey && !event.ctrlKey && !event.metaKey && !event.altKey && acceptSuggestion()) event.preventDefault();
    if (event.key === "Escape" && escape()) event.preventDefault();
    if (event.key === "Enter" && !event.shiftKey) { event.preventDefault(); form.requestSubmit(); }
  });
  form.addEventListener("submit", async (event) => {
    event.preventDefault();
    const text = input.value.trim();
    if (!text) return;
    const selected = state.selected;
    const submitted = { ...draft, input: text };
    const { edit, queuedEdit } = draft;
    const editOfId = edit?.id || null;
    const replyToId = edit ? null : draft.replyToId;
    const target = (replyToId || editOfId ? actions.replyTarget(replyToId || editOfId) : null) || queuedEdit;
    let error;
    if ((replyToId || editOfId) && !target?.sessionId) error = "This message is not in a conversation yet";
    else if (editOfId && text === target.text) error = "Change the message before sending a revision";
    else if (editOfId && !state.data.turns.some((turn) => turn.sourceId === editOfId && turn.status === "running"))
      error = "This turn has finished. Cancel the edit and use Reply for a follow-up.";
    if (error) { state.error = error; render(); focus(); return; }
    dismissSuggestion("sent");
    restore(queuedEdit?.previous || edit?.previous);
    state.error = "";
    const id = crypto.randomUUID();
    if (selected === "home") state.data.messages.push({ id, text, createdAt: new Date().toISOString(), entryId: null, replyToId, editOfId, status: target ? "routed" : "routing" });
    const sentRevision = revision;
    render();
    focus();
    try {
      if (editOfId) await api("/api/turns", "POST", { id, sessionId: target.sessionId, text, mode: "steer", editOfId });
      else if (target || selected !== "home") await api("/api/turns", "POST", { id, sessionId: target?.sessionId || selected, text, mode: "followUp", replyToId });
      else await api("/api/home", "POST", { id, text });
      if (selected === state.selected && selected !== "home") await loadSession();
    } catch (error) {
      state.error = error.message;
      if (selected === state.selected && revision === sentRevision) restore(submitted);
      state.data.messages = state.data.messages.filter((message) => message.id !== id);
      render();
    }
  });
  return { element, sync, selectView, editQueued, reconcile, handleClick };
}
