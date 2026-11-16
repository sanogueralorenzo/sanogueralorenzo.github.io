const BASE = "http://127.0.0.1:19736";
const trusted = chrome.storage.local.setAccessLevel({ accessLevel: "TRUSTED_CONTEXTS" });

const REPAIR = "Automatic pairing is unavailable or expired. Rerun the Slack browser installer, then reload Browser Hooks.";
let pairing;

async function exchange(path, body, token) {
  let response;
  try { response = await fetch(`${BASE}${path}`, {
    method: body === undefined ? "GET" : "POST", credentials: "omit", redirect: "error", cache: "no-store",
    signal: AbortSignal.timeout(8000),
    headers: { "Content-Type": "application/json", "X-Browser-Hooks-Origin": chrome.runtime.getURL("").replace(/\/$/, ""),
      ...(token ? { Authorization: `Bearer ${token}` } : {}) },
    ...(body === undefined ? {} : { body: JSON.stringify(body) }),
  }); } catch { throw new Error("Local bridge is not running. Rerun the Slack browser installer."); }
  return response;
}

async function pair() {
  // Bootstrap is an extension-private resource, never available to Slack or other websites.
  let bootstrap;
  try {
    const response = await fetch(chrome.runtime.getURL("bridge-pairing.json"), { cache: "no-store", credentials: "omit", redirect: "error" });
    if (!response.ok) throw new Error();
    bootstrap = await response.json();
  } catch { throw new Error(REPAIR); }
  if (typeof bootstrap?.code !== "string" || !/^[A-Za-z0-9_-]{20,100}$/.test(bootstrap.code)
      || !Number.isFinite(bootstrap.expiresAt) || bootstrap.expiresAt <= Date.now()) throw new Error(REPAIR);
  const response = await exchange("/pair", { code: bootstrap.code });
  if (!response.ok) throw new Error(REPAIR);
  let paired;
  try { paired = await response.json(); } catch { throw new Error(REPAIR); }
  if (typeof paired?.token !== "string" || !/^[A-Za-z0-9_-]{40,100}$/.test(paired.token)) throw new Error(REPAIR);
  await chrome.storage.local.set({ bridgeToken: paired.token });
  return paired.token;
}

async function request(path, body) {
  await trusted;
  const { bridgeToken } = await chrome.storage.local.get("bridgeToken");
  let response = bridgeToken ? await exchange(path, body, bridgeToken) : undefined;
  if (!response || response.status === 403) {
    const latest = await chrome.storage.local.get("bridgeToken");
    if (latest.bridgeToken && latest.bridgeToken !== bridgeToken) {
      response = await exchange(path, body, latest.bridgeToken);
      if (response.status !== 403) return read(response);
    }
    // One redemption serves concurrent settings, popup and job requests.
    if (!pairing) pairing = pair().finally(() => { pairing = undefined; });
    const token = await pairing;
    response = await exchange(path, body, token);
  }
  return read(response);
}

async function read(response) {
  if (response.status === 403) throw new Error(REPAIR);
  if (!response.ok) throw new Error("Local bridge rejected the request. Run browser-hooks slack status on your computer.");
  try { return await response.json(); } catch { throw new Error("Local bridge returned an invalid response. Rerun the installer."); }
}

async function settings() {
  await trusted;
  try {
    const config = await request("/config");
    if (!Array.isArray(config.keywords) || !config.keywords.every(k => typeof k === "string" && /^\S{1,40}$/.test(k))) throw new Error();
    return { keywords: config.keywords };
  } catch (error) { return { keywords: [], error: error.message }; }
}

const clients = new Set(), jobs = new Map(), updating = new Set(), dirty = new Set();
let config = { keywords: [], error: "Connecting to the local bridge…" };
let socket, opening = false, generation = 0, retry, heartbeat, handshake, attempts = 0;

function post(client, message) {
  try { client.port.postMessage(message); } catch { /* onDisconnect owns cleanup. */ }
}
function popupStatus() {
  const pages = [...clients].filter(client => !client.popup);
  const connected = !config.error && pages.some(client => client.status?.connected);
  const error = config.error || pages.find(client => client.status?.error)?.status.error;
  return { type: "status", connected, detail: error || (connected ? "Slack connected"
    : pages.length ? "Waiting for Slack to connect." : "Open Slack in this browser.") };
}
function publish() {
  const status = popupStatus();
  for (const client of clients) post(client, client.popup ? status : { type: "settings", settings: config });
}
function finish(client, id, value, error) {
  client.requests.delete(id);
  post(client, { type: "response", id, ok: !error, ...(error ? { error } : { value }) });
}
async function update(job) {
  if (!jobs.has(job)) return;
  if (updating.has(job)) { dirty.add(job); return; }
  updating.add(job);
  try {
    const value = await request(`/jobs/${job}`);
    if (["queued", "running"].includes(value.status)) return;
    const waiting = jobs.get(job);
    jobs.delete(job);
    for (const entry of waiting || []) {
      const answer = value.status === "ready" ? { job, answer: value.answer }
        : value.status === "failed" && value.error ? { job, error: value.error } : { skip: true };
      finish(entry.client, entry.id, answer);
    }
  } catch (error) {
    // A reconnect takes a fresh snapshot; never replay the original run request.
    if (!socket || socket.readyState !== WebSocket.OPEN) return;
    const waiting = jobs.get(job); jobs.delete(job);
    for (const entry of waiting || []) finish(entry.client, entry.id, undefined, error.message);
  } finally { updating.delete(job); if (dirty.delete(job)) void update(job); }
}
function stopConnection() {
  generation++; opening = false;
  clearTimeout(retry); clearTimeout(handshake); clearInterval(heartbeat);
  const old = socket; socket = undefined; old?.close();
}
function reconnect() {
  if (!clients.size || retry) return;
  retry = setTimeout(() => { retry = undefined; void connect(); }, Math.min(30000, 1000 * 2 ** Math.min(attempts++, 5)));
}
async function connect() {
  if (!clients.size || opening || socket) return;
  opening = true;
  const version = generation;
  try {
    const initial = await settings();
    if (version !== generation || !clients.size) return;
    if (initial.error) throw new Error(initial.error);
    const { bridgeToken } = await chrome.storage.local.get("bridgeToken");
    if (version !== generation || !clients.size) return;
    const stream = socket = new WebSocket("ws://127.0.0.1:19736/events");
    handshake = setTimeout(() => stream.close(), 8000);
    let lastMessage = Date.now();
    stream.onopen = () => { if (socket === stream) stream.send(JSON.stringify({ type: "authenticate", token: bridgeToken })); };
    stream.onmessage = event => {
      if (socket !== stream) return;
      lastMessage = Date.now();
      let value; try { value = JSON.parse(event.data); } catch { stream.close(); return; }
      if (value.type === "settings") {
        if (!Array.isArray(value.keywords) || !value.keywords.every(k => typeof k === "string" && /^\S{1,40}$/.test(k))) { stream.close(); return; }
        clearTimeout(handshake); clearInterval(heartbeat); attempts = 0;
        config = { keywords: value.keywords }; publish();
        for (const job of jobs.keys()) void update(job);
        // Transport keepalive, not a settings/status request. Chrome requires socket activity.
        heartbeat = setInterval(() => {
          if (Date.now() - lastMessage > 40000) stream.close();
          else if (stream.readyState === WebSocket.OPEN) stream.send(JSON.stringify({ type: "ping" }));
        }, 20000);
      } else if (value.type === "job" && /^[a-f0-9]{64}$/.test(value.job)) void update(value.job);
    };
    stream.onerror = () => stream.close();
    stream.onclose = () => {
      if (socket !== stream) return;
      socket = undefined; clearTimeout(handshake); clearInterval(heartbeat);
      config = { ...config, error: "Local bridge disconnected. Reconnecting automatically…" }; publish(); reconnect();
    };
  } catch (error) {
    if (version === generation) { config = { ...config, error: error.message }; publish(); reconnect(); }
  } finally { if (version === generation) opening = false; }
}
function cancel(client, id) {
  const entry = client.requests.get(id);
  if (!entry) return;
  entry.cancelled = true; client.requests.delete(id);
  if (entry.job) {
    const waiting = jobs.get(entry.job); waiting?.delete(entry);
    if (!waiting?.size) { jobs.delete(entry.job); void request("/cancel", { job: entry.job }).catch(() => {}); }
  }
}
async function dispatch(client, message) {
  if (client.popup) return;
  if (message?.type === "ready") { post(client, { type: "settings", settings: config }); return; }
  if (message?.type === "status") {
    client.status = { connected: message.status?.connected === true, error: typeof message.status?.error === "string" ? message.status.error.slice(0, 500) : undefined };
    for (const target of clients) if (target.popup) post(target, popupStatus());
    return;
  }
  if (typeof message?.id !== "string" || message.id.length > 100) return;
  if (message.type === "cancel") { cancel(client, message.id); return; }
  if (message.type !== "request" || client.requests.has(message.id) || client.requests.size >= 100) return;
  const entry = { client, id: message.id, cancelled: false, job: null };
  client.requests.set(message.id, entry);
  try {
    const { action, payload } = message;
    if (!["run", "claim", "delivered"].includes(action) || action !== "run" && !/^[a-f0-9]{64}$/.test(payload?.job)) throw new Error("Invalid Slack operation");
    const value = await request(`/${action}`, payload);
    if (action !== "run") { if (!entry.cancelled) finish(client, message.id, value); return; }
    if (!/^[a-f0-9]{64}$/.test(value.job)) throw new Error("Invalid bridge job");
    entry.job = value.job;
    if (entry.cancelled) { void request("/cancel", { job: entry.job }).catch(() => {}); return; }
    if (!jobs.has(entry.job)) jobs.set(entry.job, new Set());
    jobs.get(entry.job).add(entry);
    // Snapshot closes the race where completion arrived before the run response.
    void update(entry.job);
  } catch (error) { if (!entry.cancelled) finish(client, message.id, undefined, error.message || "Bridge request failed."); }
}
export function connectPort(port) {
  const sender = port.sender || {};
  let url; try { url = new URL(sender.url); } catch { port.disconnect(); return; }
  const popup = port.name === "popup" && !sender.tab && sender.url === chrome.runtime.getURL("popup/index.html");
  const slack = port.name === "slack" && sender.tab && sender.frameId === 0 && url.origin === "https://app.slack.com";
  if (!popup && !slack) { port.disconnect(); return; }
  const client = { port, popup, requests: new Map(), status: null };
  clients.add(client);
  port.onMessage.addListener(message => { void dispatch(client, message); });
  port.onDisconnect.addListener(() => {
    for (const id of client.requests.keys()) cancel(client, id);
    clients.delete(client);
    if (!clients.size) { stopConnection(); retry = undefined; }
    else for (const target of clients) if (target.popup) post(target, popupStatus());
  });
  post(client, popup ? popupStatus() : { type: "settings", settings: config });
  void connect();
}
chrome.runtime.onConnect.addListener(connectPort);
