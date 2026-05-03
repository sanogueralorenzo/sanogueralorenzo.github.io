type CodexSession = {
  id: string;
  title: string;
  cwd: string;
  status: string;
  codexThreadId: string | null;
};

type CodexEvent = {
  id: number;
  sessionId: string;
  type: string;
  data?: Record<string, unknown>;
  raw?: Record<string, unknown>;
};

const state: {
  sessions: CodexSession[];
  active: CodexSession | null;
  events: CodexEvent[];
  stream: EventSource | null;
} = {
  sessions: [],
  active: null,
  events: [],
  stream: null,
};

const $ = <T extends HTMLElement>(selector: string): T => {
  const element = document.querySelector<T>(selector);
  if (!element) throw new Error(`Missing element: ${selector}`);
  return element;
};

const sessionsEl = $("#sessions");
const eventsEl = $("#events");
const titleInput = $("#session-title") as HTMLInputElement;
const promptInput = $("#prompt") as HTMLTextAreaElement;
const statusEl = $("#status");

$("#new-session").addEventListener("click", () => createSession());
$("#send").addEventListener("click", () => sendMessage());
$("#cancel").addEventListener("click", () => cancelTurn());
promptInput.addEventListener("keydown", (event) => {
  if ((event.metaKey || event.ctrlKey) && event.key === "Enter") {
    event.preventDefault();
    void sendMessage();
  }
});

void boot();

async function boot(): Promise<void> {
  const info = await request<Record<string, unknown>>("/api/info");
  statusEl.textContent = info.version ? `Connected: ${String(info.version)}` : "Codex CLI not available";
  await loadSessions();
}

async function loadSessions(): Promise<void> {
  const response = await request<{ sessions: CodexSession[] }>("/api/sessions");
  state.sessions = response.sessions;
  renderSessions();
  if (!state.active && state.sessions[0]) openSession(state.sessions[0]);
}

async function createSession(): Promise<void> {
  const title = titleInput.value.trim() || "Untitled session";
  const session = await request<CodexSession>("/api/sessions", {
    method: "POST",
    body: JSON.stringify({ title }),
  });
  titleInput.value = "";
  state.sessions = [session, ...state.sessions];
  renderSessions();
  openSession(session);
}

function openSession(session: CodexSession): void {
  state.active = session;
  state.events = [];
  state.stream?.close();
  state.stream = new EventSource(`/api/sessions/${session.id}/events`);
  state.stream.onmessage = (message) => appendEvent(JSON.parse(message.data) as CodexEvent);
  state.stream.addEventListener("session.updated", (message) => {
    const event = JSON.parse((message as MessageEvent).data) as CodexEvent;
    appendEvent(event);
    const updated = event.data?.session as CodexSession | undefined;
    if (updated) {
      state.active = updated;
      state.sessions = state.sessions.map((item) => (item.id === updated.id ? updated : item));
      renderSessions();
    }
  });
  for (const type of [
    "session.created",
    "message.user",
    "turn.started",
    "assistant.output",
    "tool.output",
    "codex.event",
    "final.answer",
    "turn.failed",
    "turn.cancelled",
    "session.deleted",
  ]) {
    state.stream.addEventListener(type, (message) => appendEvent(JSON.parse((message as MessageEvent).data) as CodexEvent));
  }
  renderSessions();
  renderEvents();
}

async function sendMessage(): Promise<void> {
  const text = promptInput.value.trim();
  if (!state.active || !text) return;
  promptInput.value = "";
  await request(`/api/sessions/${state.active.id}/messages`, {
    method: "POST",
    body: JSON.stringify({ text }),
  });
}

async function cancelTurn(): Promise<void> {
  if (!state.active) return;
  await request(`/api/sessions/${state.active.id}/cancel`, { method: "POST" });
}

function appendEvent(event: CodexEvent): void {
  if (state.events.some((item) => item.id === event.id)) return;
  state.events.push(event);
  renderEvents();
}

function renderSessions(): void {
  sessionsEl.replaceChildren(
    ...state.sessions.map((session) => {
      const button = document.createElement("button");
      button.className = `session ${state.active?.id === session.id ? "selected" : ""}`;
      button.type = "button";
      button.innerHTML = `<span>${escapeHtml(session.title)}</span><small>${escapeHtml(session.status)} · ${escapeHtml(session.cwd)}</small>`;
      button.addEventListener("click", () => openSession(session));
      return button;
    }),
  );
}

function renderEvents(): void {
  if (!state.active) {
    eventsEl.innerHTML = `<div class="empty">Create or select a session.</div>`;
    return;
  }
  if (state.events.length === 0) {
    eventsEl.innerHTML = `<div class="empty">No events yet.</div>`;
    return;
  }
  eventsEl.replaceChildren(...state.events.map(renderEvent));
  eventsEl.scrollTop = eventsEl.scrollHeight;
}

function renderEvent(event: CodexEvent): HTMLElement {
  const article = document.createElement("article");
  article.className = `event ${event.type.replace(".", "-")}`;
  const text = eventText(event);
  article.innerHTML = `<header>${escapeHtml(event.type)} <small>#${event.id}</small></header><pre>${escapeHtml(text)}</pre>`;
  return article;
}

function eventText(event: CodexEvent): string {
  const dataText = event.data?.text ?? event.data?.message;
  if (typeof dataText === "string" && dataText.trim()) return dataText;
  if (event.type === "codex.event" && event.raw) return JSON.stringify(event.raw, null, 2);
  return JSON.stringify(event.data ?? event.raw ?? {}, null, 2);
}

async function request<T>(path: string, init?: RequestInit): Promise<T> {
  const response = await fetch(path, {
    ...init,
    headers: {
      "Content-Type": "application/json",
      ...init?.headers,
    },
  });
  if (!response.ok) throw new Error(await response.text());
  return (await response.json()) as T;
}

function escapeHtml(value: string): string {
  return value
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;");
}
