import { escapeHTML, icon, renderMessage } from "../view.js";

export function renderSession(state) {
  const messages = state.messages.length ? state.messages.map(renderMessage).join("") : '<div class="empty-session"><span class="brand-mark">✳</span><p>How can I help?</p></div>';
  const queued = state.queuedTasks.length ? `<section class="queued-card"><h2>Queued follow-ups</h2>${state.queuedTasks.map((task) => `<div class="queued-row"><span>${escapeHTML(task.text)}</span><div class="queued-actions"><button data-action="edit-queued" data-task="${escapeHTML(task.id)}">Edit</button><button data-action="remove-queued" data-task="${escapeHTML(task.id)}">Remove</button><button data-action="steer-queued" data-task="${escapeHTML(task.id)}" ${state.isRunning ? "" : "disabled"}>Steer</button></div></div>`).join("")}</section>` : "";
  return `<main class="session-scroll scroll-area"><div class="transcript">${messages}</div></main>${state.activity ? `<div class="activity-line"><i class="spinner"></i><span>${escapeHTML(state.activity)}</span></div>` : ""}${state.connectionError ? `<div class="connection-error"><span>${escapeHTML(state.connectionError)}</span><button data-action="retry">Retry</button></div>` : ""}${queued}`;
}

export function renderHeader(state) {
  const isHome = state.selectedSessionId === "home";
  return `<header class="topbar"><div class="topbar-side">${isHome ? "" : `<button class="icon-button back-button" aria-label="Back to Home" title="Back to Home" data-action="home">${icon("back", 19)}</button>`}</div><div class="brand">${isHome ? `<span class="brand-mark">${icon("sparkle", 14)}</span><strong>Agent</strong>` : ""}</div><div class="topbar-side topbar-end">${isHome ? `<button class="icon-button new-session-button" aria-label="New session" title="New session" data-action="new-session">${icon("compose", 14)}</button>` : ""}<button class="icon-button settings-trigger" aria-label="Settings" title="Settings" data-action="toggle-settings">${icon("settings", 17)}</button></div></header>`;
}
