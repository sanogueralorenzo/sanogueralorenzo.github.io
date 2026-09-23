import { post, request, uploadVoice, watchSession } from "./api.js";
import { renderComposer } from "./features/composer.js";
import { renderHome } from "./features/home.js";
import { renderHeader, renderSession } from "./features/session.js";
import { renderLoginDialog, renderSetup } from "./features/setup.js";
import { renderSettings } from "./features/settings.js";
import { escapeHTML, icon } from "./view.js";

const root = document.querySelector("#app");
const state = {
  setupStatus: null,
  apiKey: "",
  apiKeyValid: false,
  loginApiKey: "",
  loginApiKeyValid: false,
  needsSetup: false,
  setupMessage: "",
  isSettingUp: false,
  showingLogin: false,
  showingSettings: false,
  isPinned: false,
  isConnected: false,
  isRunning: false,
  isUploadingVoice: false,
  submittingSessionId: null,
  isRecording: false,
  windowClosed: false,
  connectionError: "",
  activity: "",
  selectedSessionId: null,
  selectedSessionTitle: "",
  activeRunId: null,
  homeEntries: [],
  messages: [],
  queuedTasks: [],
  input: "",
  voiceNote: null,
  optimisticRunId: null,
  completedRunIds: new Set(),
};

let stream = null;
let homeDraft = "";
let mediaRecorder = null;
let mediaStream = null;
let audioChunks = [];
let pipWindow = null;

function render() {
  if (state.windowClosed) return;
  const focusTarget = document.activeElement?.dataset?.focus;
  const selection = focusTarget ? document.activeElement.selectionStart : null;
  const oldScroll = root.querySelector(".scroll-area");
  const oldScrollPosition = oldScroll?.scrollTop ?? 0;
  const stickToBottom = oldScroll ? oldScroll.scrollHeight - oldScroll.scrollTop - oldScroll.clientHeight < 100 : true;
  if (state.needsSetup) {
    root.innerHTML = `<div class="app-shell"><header class="topbar"><div></div><div></div><div class="topbar-side topbar-end"><button class="icon-button settings-trigger" aria-label="Settings" title="Settings" data-action="toggle-settings">${icon("settings", 17)}</button></div></header>${renderSetup(state)}${renderSettings(state)}${renderLoginDialog(state)}</div>`;
  } else {
    const home = state.selectedSessionId === "home";
    root.innerHTML = `<div class="app-shell">${renderHeader(state)}${home ? `${renderHome(state)}${state.connectionError ? `<div class="connection-error home-error"><span>${escapeHTML(state.connectionError)}</span><button data-action="retry">Retry</button></div>` : ""}` : renderSession(state)}${renderComposer(state)}${renderSettings(state)}${renderLoginDialog(state)}</div>`;
  }
  const newScroll = root.querySelector(".scroll-area");
  if (newScroll) {
    newScroll.scrollTop = stickToBottom ? newScroll.scrollHeight : oldScrollPosition;
  }
  const input = focusTarget ? root.querySelector(`[data-focus="${focusTarget}"]`) : null;
  if (input) {
    input.focus({ preventScroll: true });
    if (selection !== null) input.setSelectionRange(selection, selection);
  }
}

function showError(error) {
  state.connectionError = error instanceof Error ? error.message : String(error);
  state.activity = "";
  render();
}

function closeWindow(message) {
  state.windowClosed = true;
  if (stream) stream.close();
  stream = null;
  if (mediaRecorder?.state === "recording" || mediaRecorder?.state === "paused") mediaRecorder.stop();
  mediaRecorder = null;
  for (const track of mediaStream?.getTracks() ?? []) track.stop();
  mediaStream = null;
  window.close();
  root.innerHTML = `<main class="startup">${escapeHTML(message)}</main>`;
}

async function start() {
  if (stream) stream.close();
  stream = null;
  state.activity = "";
  state.connectionError = "";
  state.isConnected = false;
  try {
    state.setupStatus = await request("/v1/setup");
    if (!state.setupStatus.configured) {
      state.needsSetup = true;
      render();
      return;
    }
    state.showingLogin = false;
    state.needsSetup = false;
    const { session } = await post("/v1/sessions/auto", {
      ...(state.selectedSessionId ? { preferredSessionId: state.selectedSessionId } : {}),
    });
    await selectSession(session.id, { keepDraft: false });
  } catch (error) {
    state.setupStatus = null;
    state.needsSetup = false;
    state.connectionError = error.message;
    render();
  }
}

async function selectSession(sessionId, options = {}) {
  if (!sessionId) return;
  if (state.selectedSessionId === "home" && options.keepDraft !== false) homeDraft = state.input;
  if (stream) stream.close();
  stream = null;
  state.selectedSessionId = sessionId;
  state.selectedSessionTitle = "";
  state.messages = [];
  state.queuedTasks = [];
  state.input = sessionId === "home" ? homeDraft : "";
  state.activeRunId = options.runId ?? null;
  state.isRunning = Boolean(options.runId);
  state.activity = state.isRunning ? "Thinking" : "";
  state.isConnected = false;
  state.submittingSessionId = null;
  state.connectionError = "";
  if (options.notice) state.messages.push({ role: "notice", text: options.notice });
  render();
  stream = watchSession(sessionId, options.runId, handleEvent, (error) => {
    if (error.message === "Reconnecting") {
      state.isConnected = false;
      if (!state.connectionError) state.activity = "Reconnecting";
    } else {
      state.connectionError = error.message;
      state.activity = "";
    }
    render();
  });
  stream.onopen = () => {
    state.isConnected = true;
    state.connectionError = "";
    if (state.activity === "Reconnecting") state.activity = "";
    render();
  };
}

function handleEvent(envelope) {
  const event = envelope.event ?? {};
  if (event.type === "home_entry") {
    replaceHomeEntry(event.entry);
    render();
    return;
  }
  if (event.type === "home_entry_removed") {
    state.homeEntries = state.homeEntries.filter((entry) => entry.id !== event.id);
    render();
    return;
  }
  if (event.type === "session_activity") {
    refreshHomeEntries();
    return;
  }
  if (envelope.sessionId !== state.selectedSessionId) return;

  switch (event.type) {
    case "snapshot":
      loadSnapshot(event.snapshot);
      break;
    case "queue":
      state.queuedTasks = event.tasks ?? [];
      break;
    case "turn": {
      if (state.optimisticRunId === envelope.runId || state.optimisticRunId === "pending") {
        const lastUser = [...state.messages].reverse().find((message) => message.role === "user");
        if (lastUser && event.text) lastUser.text = event.text;
      } else {
        appendUserTurn(event.text, event.hasAttachments);
        state.messages.push({ role: "assistant", text: "", artifacts: [] });
      }
      state.optimisticRunId = null;
      state.activeRunId = envelope.runId;
      state.isRunning = true;
      state.activity = "Thinking";
      break;
    }
    case "steer":
      appendUserTurn(event.text, false);
      break;
    case "session":
      if (event.session?.id === state.selectedSessionId) state.selectedSessionTitle = event.session.title || "Conversation";
      refreshHomeEntries();
      break;
    case "navigate":
      if (event.session?.id) {
        void selectSession(event.session.id, {
          notice: `Opened “${event.session.title || "Conversation"}”.`,
          runId: event.continues ? envelope.runId : null,
        });
        return;
      }
      break;
    case "text_delta": {
      const assistant = [...state.messages].reverse().find((message) => message.role === "assistant");
      if (assistant) assistant.text += event.delta ?? "";
      break;
    }
    case "artifact": {
      const assistant = [...state.messages].reverse().find((message) => message.role === "assistant");
      if (assistant && event.artifact) assistant.artifacts = [...(assistant.artifacts ?? []), event.artifact];
      break;
    }
    case "tool_start":
      state.activity = event.name ? `Using ${event.name.replaceAll("_", " ")}` : "Working";
      break;
    case "status":
      state.activity = event.message ?? "Working";
      break;
    case "error": {
      const assistant = [...state.messages].reverse().find((message) => message.role === "assistant");
      if (assistant && !assistant.text) assistant.text = event.message ?? "Something went wrong.";
      else if (!assistant) state.messages.push({ role: "assistant", text: event.message ?? "Something went wrong.", artifacts: [] });
      finishRun(envelope.runId);
      break;
    }
    case "done":
      finishRun(envelope.runId);
      break;
  }
  render();
}

function loadSnapshot(snapshot) {
  if (!snapshot) return;
  state.homeEntries = snapshot.homeEntries ?? [];
  state.queuedTasks = snapshot.queuedTasks ?? [];
  if (state.selectedSessionId === "home") {
    state.messages = [];
    state.activeRunId = null;
    state.isRunning = false;
    state.activity = "";
    return render();
  }
  if (snapshot.transcript?.session?.id === state.selectedSessionId) {
    state.selectedSessionTitle = snapshot.transcript.session.title || "Conversation";
  }
  if (state.messages.length === 0 && snapshot.transcript?.session?.id === state.selectedSessionId) {
    state.messages = snapshot.transcript.messages
      .filter((message) => message.role === "user" || message.role === "assistant")
      .map((message) => ({ role: message.role, text: message.content, artifacts: [] }));
  }
  const active = (snapshot.activeRuns ?? []).find((run) => run.run.sessionId === state.selectedSessionId);
  if (active) {
    if (active.navigation && active.navigation.session.id !== state.selectedSessionId) {
      void selectSession(active.navigation.session.id, { runId: active.navigation.continues ? active.run.id : null });
      return;
    }
    if (active.navigation?.continues === false) {
      state.activeRunId = active.run.id;
      state.isRunning = true;
      state.activity = "Opening conversation";
      return render();
    }
    const lastAssistant = [...state.messages].reverse().find((message) => message.role === "assistant");
    if (lastAssistant && state.optimisticRunId === active.run.id) {
      lastAssistant.text = active.output;
      lastAssistant.artifacts = active.artifacts ?? [];
    } else {
      appendUserTurn(active.turn.text, active.turn.hasAttachments);
      state.messages.push({ role: "assistant", text: active.output, artifacts: active.artifacts ?? [] });
    }
    state.activeRunId = active.run.id;
    state.optimisticRunId = active.run.id;
    state.isRunning = true;
    state.activity = "Thinking";
  } else {
    state.activeRunId = null;
    state.isRunning = false;
    state.activity = "";
  }
  render();
}

function finishRun(runId) {
  if (state.activeRunId && state.activeRunId !== runId) return;
  if (runId) {
    state.completedRunIds.add(runId);
    if (state.completedRunIds.size > 32) state.completedRunIds.delete(state.completedRunIds.values().next().value);
  }
  state.activeRunId = null;
  state.optimisticRunId = null;
  state.isRunning = false;
  state.activity = "";
}

function appendUserTurn(text, hasAttachments) {
  const displayed = text?.trim() || (hasAttachments ? "Voice message" : "Message");
  const last = state.messages.at(-1);
  if (last?.role !== "user" || last.text !== displayed) state.messages.push({ role: "user", text: displayed, artifacts: [] });
}

function replaceHomeEntry(entry) {
  if (!entry) return;
  const index = state.homeEntries.findIndex((item) => item.id === entry.id);
  if (index < 0) state.homeEntries.push(entry);
  else state.homeEntries[index] = entry;
  state.homeEntries.sort((a, b) => a.updatedAt.localeCompare(b.updatedAt));
}

async function refreshHomeEntries() {
  try {
    const result = await request("/v1/sessions");
    state.homeEntries = result.homeEntries;
    render();
  } catch (error) { showError(error); }
}

async function send() {
  const text = state.input.trim();
  const note = state.voiceNote;
  if ((!text && !note) || !state.isConnected || state.isUploadingVoice
    || (state.isRunning && state.selectedSessionId !== "home" && note)) return;
  const selected = state.selectedSessionId;
  if (!selected) return;
  if (selected !== "home" && state.submittingSessionId === selected) return;
  state.isUploadingVoice = Boolean(note);
  state.connectionError = "";
  render();
  let attachmentIds = [];
  if (note) {
    try {
      const uploaded = await uploadVoice(note);
      attachmentIds = [uploaded.id];
    } catch (error) {
      state.isUploadingVoice = false;
      showError(error);
      return;
    }
  }
  state.isUploadingVoice = false;
  state.input = "";
  state.voiceNote = null;
  const displayText = text || "Voice message";

  if (selected === "home") {
    const requestId = crypto.randomUUID();
    replaceHomeEntry({ id: requestId, sessionId: null, body: displayText, requests: [{ text: displayText, createdAt: new Date().toISOString() }], summary: null, state: "routing", url: null, updatedAt: new Date().toISOString() });
    render();
    try {
      await post("/v1/runs", { text, sessionId: selected, requestId, attachmentIds, channel: "macos" });
    } catch (error) {
      replaceHomeEntry({ id: requestId, sessionId: null, body: displayText, requests: [], summary: error.message, state: "failed", url: null, updatedAt: new Date().toISOString() });
      state.voiceNote = note;
      showError(error);
      return;
    }
    return;
  }

  if (state.isRunning) {
    try {
      await post("/v1/follow-ups", { sessionId: selected, text, channel: "macos" });
      render();
    } catch (error) {
      state.input = state.input ? `${text}\n\n${state.input}` : text;
      showError(error);
    }
    return;
  }

  state.messages.push({ role: "user", text: displayText, artifacts: [] });
  state.optimisticRunId = "pending";
  state.submittingSessionId = selected;
  render();
  try {
    const { run } = await post("/v1/runs", { text, sessionId: selected, attachmentIds, channel: "macos" });
    if (state.selectedSessionId !== selected) return;
    if (run) {
      if (state.completedRunIds.delete(run.id)) return;
      state.activeRunId = run.id;
      state.optimisticRunId = run.id;
      state.isRunning = true;
      state.activity = "Thinking";
      render();
    }
  } catch (error) {
    if (state.selectedSessionId !== selected) return;
    state.messages.pop();
    state.input = text;
    state.voiceNote = note;
    state.optimisticRunId = null;
    state.activity = "Agent is already working";
    showError(error);
  } finally {
    if (state.submittingSessionId === selected) state.submittingSessionId = null;
  }
}

async function loginWithChatGPT() {
  if (state.isSettingUp) return;
  state.isSettingUp = true;
  state.setupMessage = "Opening ChatGPT sign-in…";
  render();
  const popup = window.open("about:blank", "agent-chatgpt-login");
  if (!popup) {
    state.isSettingUp = false;
    state.setupMessage = "Allow pop-ups for this local Agent page, then try signing in again.";
    render();
    return;
  }
  try {
    const login = await post("/v1/setup/codex/login", { mode: "browser" });
    if (login.type !== "chatgpt" || !login.authUrl) throw new Error("Agent expected browser login but received another login flow.");
    state.setupMessage = "Finish signing in in your browser.";
    render();
    popup.location.href = login.authUrl;
    const result = await post(`/v1/setup/codex/login/${encodeURIComponent(login.loginId)}/wait`, {});
    if (result.state !== "complete") throw new Error(result.error ?? "ChatGPT sign-in failed.");
    state.isSettingUp = false;
    state.setupMessage = "";
    await start();
  } catch (error) {
    popup?.close();
    state.isSettingUp = false;
    state.setupMessage = error.message;
    render();
  }
}

async function connectApiKey(form) {
  const key = new FormData(form).get("apiKey");
  if (typeof key !== "string" || !key.startsWith("sk-")) return;
  const loginForm = form.dataset.form === "login-api-key";
  state[loginForm ? "loginApiKey" : "apiKey"] = "";
  state[loginForm ? "loginApiKeyValid" : "apiKeyValid"] = false;
  state.isSettingUp = true;
  state.setupMessage = "Connecting API key…";
  render();
  try {
    await post("/v1/setup/openai", { apiKey: key });
    form.reset();
    state.isSettingUp = false;
    state.setupMessage = "";
    await start();
  } catch (error) {
    state.isSettingUp = false;
    state.setupMessage = error.message;
    render();
  }
}

async function logout() {
  if (!window.confirm("This signs out of the Codex profile shared by Agent, Codex CLI, and the Codex app on this Mac. Continue?")) return;
  try {
    await post("/v1/setup/logout", {});
    state.setupStatus = null;
    state.needsSetup = true;
    state.showingSettings = false;
    state.messages = [];
    render();
    await start();
  } catch (error) { showError(error); }
}

async function toggleRecording() {
  if (state.isRecording) {
    mediaRecorder?.stop();
    for (const track of mediaStream?.getTracks() ?? []) track.stop();
    mediaStream = null;
    state.isRecording = false;
    render();
    return;
  }
  try {
    mediaStream = await navigator.mediaDevices.getUserMedia({ audio: true });
    const preferred = ["audio/mp4", "audio/webm;codecs=opus", "audio/webm", "audio/ogg;codecs=opus"];
    const mimeType = preferred.find((type) => MediaRecorder.isTypeSupported(type));
    mediaRecorder = mimeType ? new MediaRecorder(mediaStream, { mimeType }) : new MediaRecorder(mediaStream);
    audioChunks = [];
    mediaRecorder.ondataavailable = (event) => { if (event.data.size) audioChunks.push(event.data); };
    mediaRecorder.onstop = () => {
      const blob = new Blob(audioChunks, { type: mediaRecorder?.mimeType || "audio/webm" });
      const extension = blob.type.includes("mp4") ? "m4a" : blob.type.includes("ogg") ? "ogg" : "webm";
      state.voiceNote = new File([blob], `agent-voice-note.${extension}`, { type: blob.type });
      render();
    };
    mediaRecorder.start();
    state.isRecording = true;
    render();
  } catch (error) {
    state.connectionError = error instanceof Error ? error.message : "Allow microphone access to record a voice note.";
    render();
  }
}

async function pinWindow() {
  state.showingSettings = false;
  if (pipWindow) {
    pipWindow.close();
    pipWindow = null;
    state.isPinned = false;
    render();
    return;
  }
  if (!("documentPictureInPicture" in window)) {
    state.connectionError = "Pin Window is available in Chrome or Edge.";
    render();
    return;
  }
  try {
    pipWindow = await window.documentPictureInPicture.requestWindow({ width: 720, height: 640 });
    for (const sheet of document.styleSheets) {
      if (sheet.href) {
        const link = pipWindow.document.createElement("link");
        link.rel = "stylesheet";
        link.href = sheet.href;
        pipWindow.document.head.append(link);
      }
    }
    pipWindow.document.body.style.cssText = "margin:0;width:100vw;height:100vh;overflow:hidden";
    pipWindow.document.documentElement.style.cssText = "width:100%;height:100%";
    pipWindow.document.body.append(root);
    state.isPinned = true;
    pipWindow.addEventListener("pagehide", () => {
      document.body.append(root);
      pipWindow = null;
      state.isPinned = false;
      render();
    }, { once: true });
    render();
  } catch (error) { showError(error); }
}

async function quitAgent() {
  try {
    const { closed } = await post("/v1/control/quit", {});
    state.showingSettings = false;
    closeWindow(`${closed ? "The website server is closed." : "You can close this tab to quit Agent."} Background work will continue.`);
  } catch (error) { showError(error); }
}

root.addEventListener("input", (event) => {
  if (event.target.matches('[data-form$="api-key"] input')) {
    const loginForm = event.target.form?.dataset.form === "login-api-key";
    const keyName = loginForm ? "loginApiKey" : "apiKey";
    const validName = `${keyName}Valid`;
    state[keyName] = event.target.value;
    state[validName] = event.target.value.startsWith("sk-");
    const button = event.target.form?.querySelector("button");
    if (button) button.disabled = state.isSettingUp || state.setupStatus?.codex?.installed !== true || !state[validName];
  }
  if (event.target.matches('[data-focus="composer"]')) {
    state.input = event.target.value;
    event.target.style.height = "38px";
    event.target.style.height = `${Math.min(event.target.scrollHeight, 144)}px`;
    const hasContent = state.input.trim() || state.voiceNote;
    if (hasContent !== Boolean(root.querySelector(".send-button"))) render();
  }
});

root.addEventListener("keydown", (event) => {
  if (event.target.matches('[data-focus="composer"]') && event.key === "Enter" && !event.shiftKey) {
    event.preventDefault();
    void send();
  }
});

root.addEventListener("submit", (event) => {
  if (event.target.matches('[data-form="api-key"], [data-form="login-api-key"]')) {
    event.preventDefault();
    void connectApiKey(event.target);
  }
});

root.addEventListener("change", (event) => {
  if (event.target.id !== "voice-file") return;
  const file = event.target.files?.[0];
  if (!file) return;
  const extension = file.name.split(".").at(-1)?.toLowerCase();
  if (!["m4a", "mp3", "wav", "ogg", "webm"].includes(extension)) {
    state.connectionError = "Choose an M4A, MP3, WAV, OGG, or WebM voice note.";
  } else {
    state.voiceNote = file;
    state.connectionError = "";
  }
  render();
});

root.addEventListener("click", async (event) => {
  const button = event.target.closest("[data-action]");
  if (!button) return;
  const action = button.dataset.action;
  if (action === "close-settings" && event.target.closest("[data-menu]")) return;
  if (action === "close-login" && event.target.closest(".login-dialog")) return;
  switch (action) {
    case "home":
      await selectSession("home");
      break;
    case "open-session":
      await selectSession(button.dataset.session);
      break;
    case "toggle-settings":
      state.showingSettings = !state.showingSettings;
      render();
      break;
    case "close-settings":
      state.showingSettings = false;
      render();
      break;
    case "open-login":
      state.showingSettings = false;
      state.showingLogin = true;
      render();
      break;
    case "close-login":
      state.showingLogin = false;
      render();
      break;
    case "login-chatgpt":
      await loginWithChatGPT();
      break;
    case "logout":
      await logout();
      break;
    case "pin-window":
      await pinWindow();
      break;
    case "quit":
      await quitAgent();
      break;
    case "pick-voice":
      root.querySelector("#voice-file")?.click();
      break;
    case "remove-voice":
      state.voiceNote = null;
      render();
      break;
    case "toggle-recording":
      await toggleRecording();
      break;
    case "send":
      await send();
      break;
    case "stop":
      if (state.activeRunId) {
        try { await post("/v1/runs/stop", { runId: state.activeRunId }); }
        catch (error) { showError(error); }
      }
      break;
    case "retry":
      await start();
      break;
    case "edit-queued": {
      const task = state.queuedTasks.find((item) => item.id === button.dataset.task);
      if (task) {
        try {
          const { task: removed } = await post("/v1/follow-ups/remove", { sessionId: task.sessionId, taskId: task.id });
          state.input = state.input ? `${removed.text}\n\n${state.input}` : removed.text;
          render();
          root.querySelector('[data-focus="composer"]')?.focus();
        } catch (error) { showError(error); }
      }
      break;
    }
    case "remove-queued":
    case "steer-queued": {
      const task = state.queuedTasks.find((item) => item.id === button.dataset.task);
      if (!task) break;
      try {
        if (action === "remove-queued") await post("/v1/follow-ups/remove", { sessionId: task.sessionId, taskId: task.id });
        else if (state.activeRunId) {
          const { steered } = await post("/v1/follow-ups/steer", { sessionId: task.sessionId, taskId: task.id, runId: state.activeRunId });
          if (!steered) showError(new Error("That turn has finished. The follow-up remains queued."));
        }
      } catch (error) { showError(error); }
      break;
    }
  }
});

document.addEventListener("keydown", (event) => {
  if (event.key === "Escape") {
    if (state.showingLogin) state.showingLogin = false;
    else if (state.showingSettings) state.showingSettings = false;
    else if (state.selectedSessionId === "home") {
      closeWindow("Close this tab to close Agent. Background work will continue.");
      return;
    } else if (state.selectedSessionId) void selectSession("home");
    else return;
    render();
  }
});

render();
void start();
