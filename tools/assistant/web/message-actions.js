import { escapeHTML, icon } from "./view.js";

const approvalText = "Yes, go ahead.";

export function createMessageActions({ state, root, api, render }) {
  const pending = new Set();

  function replyTarget(id) {
    if (!id) return null;
    const message = state.data.messages.find((item) => item.id === id);
    if (message) return { role: "You", text: message.text, sessionId: state.data.entries.find((entry) => entry.id === message.entryId)?.sessionId };
    for (const entry of state.data.entries) {
      const update = entry.updates.find((item) => item.id === id);
      if (update) return { role: "Assistant", text: update.text, sessionId: entry.sessionId };
    }
    const reply = state.transcript.find((message) => message.id === id && message.role === "assistant");
    return reply ? { role: "Assistant", text: reply.text, sessionId: state.selected } : null;
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
  function reactionTo(id) {
    return state.data.messages.find((message) => message.replyToId === id && message.reaction === "thumbs-up");
  }
  function thumbsUpButton(id, sessionId) {
    if (!id || !sessionId) return "";
    const sending = pending.has(id);
    const sent = !!reactionTo(id) && !sending;
    const label = sending ? "Sending…" : sent ? "Go ahead sent" : "Go ahead";
    return `<button type="button" class="reply-action thumbs-up-action ${sending ? "pending" : sent ? "sent" : ""}" ${sent ? 'aria-disabled="true"' : 'data-action="thumbs-up"'} data-reply="${escapeHTML(id)}" data-session="${escapeHTML(sessionId)}" aria-label="${label}" title="${label}" ${sending ? "disabled" : ""}>${sent ? '<span aria-hidden="true">👍</span>' : icon("thumbs-up", 14)}</button>`;
  }
  function replyActions(id, sessionId) {
    return `<div class="message-actions">${thumbsUpButton(id, sessionId)}${replyButton(id, sessionId)}</div>`;
  }
  function requestAction(message, sessionId) {
    const active = state.data.turns.some((turn) => turn.sourceId === message.id && turn.status === "running");
    return active ? `<button type="button" class="reply-action" data-action="edit" data-edit="${escapeHTML(message.id)}" aria-label="Edit active message" title="Edit and steer">${icon("edit", 14)}</button>` : replyButton(message.id, sessionId);
  }
  function preview() {
    const editing = state.selected === "home" && state.edit;
    const target = replyTarget(editing ? state.edit.id : state.replyToId);
    if (!target) return "";
    return `<div class="reply-preview">${quote(editing ? { role: "Editing message", text: target.text } : target, "reply-preview-text")}<button type="button" class="dismiss-reply" data-action="${editing ? "dismiss-edit" : "dismiss-reply"}" aria-label="${editing ? "Cancel edit" : "Cancel reply"}" title="${editing ? "Cancel edit" : "Cancel reply"}">${icon("close", 16)}</button></div>`;
  }
  function refreshComposer() {
    render(true);
    root.querySelector("textarea")?.focus();
  }
  async function approve(button) {
    const replyToId = button.dataset.reply;
    if (pending.has(replyToId) || reactionTo(replyToId)) return;
    const sessionId = button.dataset.session;
    const id = crypto.randomUUID();
    const entry = state.data.entries.find((item) => item.updates.some((update) => update.id === replyToId))
      || [...state.data.entries].reverse().find((item) => item.sessionId === sessionId);
    pending.add(replyToId);
    state.error = "";
    state.data.messages.push({ id, text: approvalText, createdAt: new Date().toISOString(), entryId: entry?.id || null, replyToId, reaction: "thumbs-up", status: "routed" });
    render();
    try {
      await api("/api/turns", "POST", { id, sessionId, text: approvalText, mode: "followUp", replyToId, reaction: "thumbs-up" });
    } catch (error) {
      state.data.messages = state.data.messages.filter((message) => message.id !== id);
      throw error;
    } finally {
      pending.delete(replyToId);
      render();
    }
  }
  async function handleClick(button) {
    switch (button.dataset.action) {
      case "thumbs-up":
        await approve(button);
        return true;
      case "reply": {
        const target = replyTarget(button.dataset.reply);
        if (target?.sessionId) {
          state.input = root.querySelector("textarea")?.value || "";
          state.edit = null;
          state.replyToId = button.dataset.reply;
          refreshComposer();
        }
        return true;
      }
      case "edit": {
        const message = state.data.messages.find((item) => item.id === button.dataset.edit);
        if (message && state.data.turns.some((turn) => turn.sourceId === message.id && turn.status === "running")) {
          state.edit = { id: message.id, previousInput: root.querySelector("textarea")?.value || "", previousReplyToId: state.replyToId };
          state.replyToId = null;
          state.input = message.text;
          refreshComposer();
        }
        return true;
      }
      case "dismiss-reply":
        state.input = root.querySelector("textarea")?.value || "";
        state.replyToId = null;
        refreshComposer();
        return true;
      case "dismiss-edit":
        state.input = state.edit?.previousInput || "";
        state.replyToId = state.edit?.previousReplyToId || null;
        state.edit = null;
        refreshComposer();
        return true;
      default:
        return false;
    }
  }

  return { replyTarget, quote, reactionTo, replyActions, requestAction, preview, handleClick };
}
