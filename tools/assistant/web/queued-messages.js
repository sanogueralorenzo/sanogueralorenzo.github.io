import { escapeHTML, icon } from "./view.js";

export function composerDraft(state) {
  return { input: state.input, replyToId: state.replyToId, edit: state.edit, queuedEdit: state.queuedEdit };
}
export function restoreComposerDraft(state, draft) {
  Object.assign(state, { input: "", replyToId: null, edit: null, queuedEdit: null }, draft);
}

export function createQueuedMessages({ state, root, api, render }) {
  const pending = new Set();
  function controls(turn, hover = false) {
    const disabled = pending.has(turn.id) ? "disabled" : "";
    const button = (action, label, symbol) => `<button type="button" class="${hover ? "reply-action" : "queue-action"}" data-action="${action}" data-turn="${escapeHTML(turn.id)}" data-session="${escapeHTML(turn.sessionId)}" aria-label="${label}" title="${label}" ${disabled}>${icon(symbol, 14)}</button>`;
    const running = state.data.turns.some((item) => item.sessionId === turn.sessionId && item.status === "running");
    const steer = !hover && running ? `<button type="button" class="queue-steer" data-action="steer-queued" data-turn="${escapeHTML(turn.id)}" data-session="${escapeHTML(turn.sessionId)}" aria-label="Steer with this queued message" title="Use this message after the current tool finishes" ${disabled}>Steer</button>` : "";
    return `<div class="${hover ? "message-actions" : "queued-actions"}">${steer}${button("edit-queued", "Edit queued message", "edit")}${button("delete-queued", "Delete queued message", "trash")}</div>`;
  }
  function composer() {
    const turns = state.data.turns.filter((turn) => turn.sessionId === state.selected && turn.status === "queued");
    return turns.length ? `<section class="queued-card" aria-label="Queued messages"><h2>Queued follow-ups</h2>${turns.map((turn) => `<div class="queued-row"><span>${state.data.messages.find((message) => message.id === turn.sourceId)?.reaction ? "👍 Go ahead" : escapeHTML(turn.text)}</span>${controls(turn)}</div>`).join("")}</section>` : "";
  }
  function cancelEdit() {
    if (!state.queuedEdit) return false;
    restoreComposerDraft(state, state.queuedEdit.previous);
    render(true);
    root.querySelector("textarea")?.focus();
    return true;
  }
  async function handleClick(button) {
    const action = button.dataset.action;
    if (action === "dismiss-queued-edit") { cancelEdit(); return true; }
    if (!["edit-queued", "delete-queued", "steer-queued"].includes(action)) return false;
    const turnId = button.dataset.turn;
    if (pending.has(turnId)) return true;
    const view = state.selected;
    pending.add(turnId);
    render();
    try {
      const { turn, message, removedMessageId } = await api(action === "steer-queued" ? "/api/steer-queued" : "/api/dequeue", "POST", { turnId, sessionId: button.dataset.session });
      state.data.turns = state.data.turns.filter((item) => item.id !== turnId);
      if (removedMessageId) state.data.messages = state.data.messages.filter((item) => item.id !== removedMessageId);
      if (action === "edit-queued") {
        const previous = view === state.selected ? composerDraft(state) : state.sessionDrafts[view];
        const draft = { input: message?.text || turn.text, replyToId: turn.replyToId || null, edit: null,
          queuedEdit: { sessionId: turn.sessionId, text: message?.text || turn.text, previous } };
        if (view === state.selected) restoreComposerDraft(state, draft);
        else state.sessionDrafts[view] = draft;
      }
    } finally {
      pending.delete(turnId);
      render(true);
      if (action === "edit-queued" && view === state.selected) root.querySelector("textarea")?.focus();
    }
    return true;
  }
  return { controls, composer, cancelEdit, handleClick };
}
