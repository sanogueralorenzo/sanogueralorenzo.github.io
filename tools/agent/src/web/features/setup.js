import { escapeHTML, icon } from "../view.js";

export function renderSetup(state) {
  const needsCodexInstall = state.setupStatus?.codex?.installed === false;
  return `<main class="setup-view"><section class="onboarding-transcript" aria-label="Welcome to Agent">
    <article class="message-row assistant-row"><div class="message-bubble assistant-bubble"><div class="message-text markdown-content"><p>Hey, I’m Agent — your local coordinator for AI work on this Mac.</p></div></div></article>
    <article class="message-row assistant-row"><div class="message-bubble assistant-bubble"><div class="message-text markdown-content"><p>${needsCodexInstall ? "First install Codex CLI on this Mac. Then connect your ChatGPT profile or an OpenAI API key." : "To get started, connect your Codex profile. You can sign in with ChatGPT using the profile already installed on this Mac, or connect an OpenAI API key."}</p></div></div></article>
    <article class="message-row assistant-row"><div class="message-bubble assistant-bubble"><div class="message-text markdown-content"><p>Here’s how I work:</p><ul><li>Tell me what you want done in Main chat, and I’ll route it to a Codex conversation.</li><li>Follow concise progress and results here, then open a side chat to continue the work.</li><li>Your Agent runtime and saved task history stay on this Mac.</li></ul></div></div></article>
    <article class="message-row assistant-row"><div class="message-bubble assistant-bubble onboarding-connect"><div class="message-text markdown-content"><p>${needsCodexInstall ? "Once Codex CLI is installed, connect your account here." : "Connect an account below and we can get started."}</p></div>${renderControls(state, false)}</div></article>
  </section></main>`;
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
  return `<div class="sign-in-controls"><button class="primary-button" data-action="login-chatgpt" ${state.isSettingUp || status?.codex?.installed !== true ? "disabled" : ""}>Sign in with ChatGPT</button>${status?.codex?.installed === false ? '<p class="muted-copy small-copy">Install Codex CLI on this Mac to connect Agent.</p>' : ""}<div class="or-divider"><span></span><small>or</small><span></span></div><form data-form="${loginForm ? "login-api-key" : "api-key"}"><div class="api-key-row"><input name="apiKey" type="password" autocomplete="off" placeholder="OpenAI API key" aria-label="OpenAI API key" value="${escapeHTML(key)}"><button class="secondary-button" ${connectDisabled ? "disabled" : ""}>Connect</button></div></form>${state.isSettingUp ? '<div class="setup-progress"><i class="spinner"></i></div>' : ""}${state.setupMessage ? `<p class="muted-copy setup-message">${escapeHTML(state.setupMessage)}</p>` : ""}</div>`;
}
