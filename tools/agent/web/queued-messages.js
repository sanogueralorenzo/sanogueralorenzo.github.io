import { escapeHTML, icon } from "./view.js";

export function createQueuedMessages({ state, api, render, composer }) {
  const pending = new Set();
  function controls(turn, hover = false) {
    const disabled = pending.has(turn.id) ? "disabled" : "";
    const button = (action, label, symbol) => `<button type="button" class="${hover ? "reply-action" : "queue-action"}" data-action="${action}" data-turn="${escapeHTML(turn.id)}" data-session="${escapeHTML(turn.sessionId)}" aria-label="${label}" title="${label}" ${disabled}>${icon(symbol, 14)}</button>`;
    const running = state.data.turns.some((item) => item.sessionId === turn.sessionId && item.status === "running");
    const steer = !hover && running ? button("steer-queued", "Steer with this message", "steer") : "";
    return `<div class="${hover ? "message-actions" : "queued-actions"}">${steer}${button("edit-queued", "Edit queued message", "edit")}${button("delete-queued", "Delete queued message", "trash")}</div>`;
  }
  function html() {
    const turns = state.data.turns.filter((turn) => turn.sessionId === state.selected && turn.status === "queued");
    return turns.length ? `<section class="queued-card" aria-label="Queued messages"><h2>Queued follow-ups</h2>${turns.map((turn) => `<div class="queued-row"><span>${state.data.messages.find((message) => message.id === turn.sourceId)?.reaction ? "👍 Go ahead" : escapeHTML(turn.text)}${turn.dependsOn?.length ? `<small>Waiting for: ${turn.dependsOn.map(id => escapeHTML(state.data.messages.find(message => message.id === id)?.text || "earlier task")).join("; ")}</small>` : ""}</span>${controls(turn)}</div>`).join("")}</section>` : "";
  }
  async function handleClick(button) {
    const action = button.dataset.action;
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
      if (action === "edit-queued") composer.editQueued(view, turn, message?.text || turn.text);
    } finally {
      pending.delete(turnId);
      render();
    }
    return true;
  }
  return { controls, html, handleClick };
}
