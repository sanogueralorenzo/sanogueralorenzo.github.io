import { escapeHTML, icon } from "../view.js";

export function renderSettings(state) {
  if (!state.showingSettings) return "";
  const items = state.setupStatus?.configured
    ? `<button data-action="logout" ${state.isSettingUp ? "disabled" : ""}>Sign Out of Codex on This Mac…</button>`
    : `<button data-action="open-login">Connect Codex…</button>`;
  return `<div class="settings-backdrop" data-action="close-settings"><section class="settings-menu" role="menu" aria-label="Settings" data-menu="settings">${items}<hr><button data-action="pin-window">${icon("pin", 15)}<span>${state.isPinned ? "Unpin Window" : "Pin Window"}</span></button><hr><button data-action="quit">Quit Agent</button></section></div>`;
}

export function renderSessionMenu(state) {
  if (!state.showingSessions) return "";
  return `<div class="settings-backdrop" data-action="close-sessions"><section class="settings-menu session-menu" role="menu" aria-label="Recent sessions" data-menu="sessions">${state.sessions.length ? state.sessions.map((session) => `<button data-action="open-session" data-session="${escapeHTML(session.id)}"><span>${escapeHTML(session.title || "Untitled session")}</span>${session.activeRunId ? '<i class="spinner"></i>' : ""}</button>`).join("") : '<p class="no-sessions">No sessions yet</p>'}</section></div>`;
}
