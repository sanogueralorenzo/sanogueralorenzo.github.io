import { escapeHTML, icon } from "../view.js";

export function renderSetup(state) {
  return `<main class="setup-view"><div class="setup-content"><span class="setup-mark">${icon("sparkle", 16)}</span><h1>Agent</h1><p>Connect your Codex profile for this Mac. Agent shares its login and tools with Codex.</p>${renderControls(state, false)}</div></main>`;
}

export function renderLoginDialog(state) {
  if (!state.showingLogin) return "";
  return `<div class="modal-backdrop" data-action="close-login"><section class="login-dialog" role="dialog" aria-modal="true" aria-labelledby="login-title"><h2 id="login-title">Connect Codex</h2><p class="muted-copy">This uses the same profile as Codex on this Mac.</p>${renderControls(state, true)}<div class="dialog-footer"><button class="subtle-button" data-action="close-login">Close</button></div></section></div>`;
}

function renderControls(state, loginForm) {
  const status = state.setupStatus;
  const key = loginForm ? state.loginApiKey : state.apiKey;
  const keyValid = loginForm ? state.loginApiKeyValid : state.apiKeyValid;
  const connectDisabled = state.isSettingUp || status?.codex?.installed !== true || !keyValid;
  return `<div class="sign-in-controls"><button class="primary-button" data-action="login-chatgpt" ${state.isSettingUp || status?.codex?.installed !== true ? "disabled" : ""}>Sign in with ChatGPT</button>${status?.codex?.installed === false ? '<p class="muted-copy small-copy">Codex CLI is required for ChatGPT.</p>' : ""}<div class="or-divider"><span></span><small>or</small><span></span></div><form data-form="${loginForm ? "login-api-key" : "api-key"}"><div class="api-key-row"><input name="apiKey" type="password" autocomplete="off" placeholder="OpenAI API key" aria-label="OpenAI API key" value="${escapeHTML(key)}"><button class="secondary-button" ${connectDisabled ? "disabled" : ""}>Connect</button></div></form>${state.isSettingUp ? '<div class="setup-progress"><i class="spinner"></i></div>' : ""}${state.setupMessage ? `<p class="muted-copy setup-message">${escapeHTML(state.setupMessage)}</p>` : ""}</div>`;
}
