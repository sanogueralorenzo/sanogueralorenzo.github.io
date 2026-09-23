import { escapeHTML, icon } from "../view.js";

export function renderSetup(state) {
  return `<main class="setup-view"><div class="setup-content"><span class="setup-mark">${icon("sparkle", 16)}</span><h1>Agent</h1><p>Connect once, then continue from anywhere.</p>${renderControls(state)}</div></main>`;
}

export function renderLoginDialog(state) {
  if (!state.showingLogin) return "";
  return `<div class="modal-backdrop" data-action="close-login"><section class="login-dialog" role="dialog" aria-modal="true" aria-labelledby="login-title"><h2 id="login-title">Log In</h2>${renderControls(state)}<div class="dialog-footer"><button class="subtle-button" data-action="close-login">Close</button></div></section></div>`;
}

function renderControls(state) {
  const status = state.setupStatus;
  return `<div class="sign-in-controls"><button class="primary-button" data-action="login-chatgpt" ${state.isSettingUp || status?.codex?.installed !== true ? "disabled" : ""}>Sign in with ChatGPT</button>${status?.codex?.installed === false ? '<p class="muted-copy small-copy">Codex CLI is required for ChatGPT.</p>' : ""}<div class="or-divider"><span></span><small>or</small><span></span></div><form data-form="api-key"><div class="api-key-row"><input name="apiKey" type="password" autocomplete="off" placeholder="OpenAI API key" aria-label="OpenAI API key"><button class="secondary-button" ${state.isSettingUp || status?.codex?.installed !== true ? "disabled" : ""}>Connect</button></div></form>${state.isSettingUp ? '<div class="setup-progress"><i class="spinner"></i></div>' : ""}${state.setupMessage ? `<p class="muted-copy setup-message">${escapeHTML(state.setupMessage)}</p>` : ""}</div>`;
}

