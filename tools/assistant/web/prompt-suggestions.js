export function suggestionTarget(state) {
  if (!state.connected || (state.selected === "home" && state.edit)) return null;
  let target;
  if (state.selected === "home") {
    if (state.data.turns.length || state.data.messages.some((message) => message.status === "routing")) return null;
    const replies = state.data.entries.flatMap((entry) => entry.updates.filter((update) => update.kind !== "progress")
      .map((update) => ({ sessionId: entry.sessionId, replyId: update.id, createdAt: update.createdAt, kind: update.kind })));
    const last = replies.sort((a, b) => a.createdAt.localeCompare(b.createdAt)).at(-1);
    if (last?.kind !== "result" || state.data.messages.some((message) => message.createdAt > last.createdAt)) return null;
    target = { sessionId: last.sessionId, replyId: last.replyId };
  } else {
    const last = state.transcript.at(-1);
    if (!last?.completed) return null;
    target = { sessionId: state.selected, replyId: last.id };
  }
  const record = state.data.sessions.find((session) => session.id === target.sessionId);
  if (record?.status !== "idle" || state.data.turns.some((turn) => turn.sessionId === target.sessionId)) return null;
  return state.replyToId && state.replyToId !== target.replyId ? null : target;
}

export function createPromptSuggestions({ state, root, api, render }) {
  const cache = new Map();
  const dismissed = new Map();

  function available() {
    const target = suggestionTarget(state);
    const cached = target && cache.get(target.sessionId);
    return target && !state.input && dismissed.get(target.sessionId)?.replyId !== target.replyId && cached?.replyId === target.replyId && cached.text
      ? { ...target, text: cached.text } : null;
  }
  function paint() {
    const hint = available();
    const overlay = root.querySelector(".prompt-suggestion");
    const textarea = root.querySelector('[data-focus="composer"]');
    if (!overlay || !textarea) return;
    overlay.hidden = !hint;
    textarea.placeholder = hint ? "" : "Message";
    if (!hint) { textarea.removeAttribute("aria-description"); return; }
    overlay.querySelector("span").textContent = hint.text;
    overlay.querySelector("button").setAttribute("aria-label", `Use suggested reply: ${hint.text}`);
    textarea.setAttribute("aria-description", `Suggested reply: ${hint.text}. Press Tab to use it.`);
  }
  function sync() {
    const target = suggestionTarget(state);
    const dismissal = target && dismissed.get(target.sessionId);
    if (dismissal?.reason === "draft" && !state.input && !state.replyToId && !state.edit) dismissed.delete(target.sessionId);
    if (target && !state.input && dismissed.get(target.sessionId)?.replyId !== target.replyId && cache.get(target.sessionId)?.replyId !== target.replyId) {
      const value = { replyId: target.replyId, text: null };
      cache.set(target.sessionId, value);
      void api("/api/suggestions", "POST", target).then((result) => {
        value.text = typeof result.text === "string" ? result.text : null;
      }).catch(() => {}).finally(paint);
    }
    paint();
  }
  function dismiss(reason = "escape") {
    const target = suggestionTarget(state);
    if (target) dismissed.set(target.sessionId, { replyId: target.replyId, reason });
    if (reason === "draft") sync();
    else paint();
  }
  function accept() {
    const hint = available();
    if (!hint) return false;
    dismissed.set(hint.sessionId, { replyId: hint.replyId, reason: "draft" });
    state.input = hint.text;
    state.replyToId = hint.replyId;
    render(true);
    const textarea = root.querySelector('[data-focus="composer"]');
    textarea?.focus();
    textarea?.setSelectionRange(hint.text.length, hint.text.length);
    return true;
  }
  return { sync, dismiss, accept };
}
