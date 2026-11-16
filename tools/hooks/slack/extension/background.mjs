import { request, subscribe } from "../../bridge.mjs";

const clients = new Set();
let config = { keywords: [], error: "Connecting to the local bridge…" };
let unsubscribe;

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
function pendingRequests() {
  return [...clients].flatMap(client => [...client.requests.values()]);
}
function finish(entry, value, error) {
  const { client, id } = entry;
  if (client.requests.get(id) !== entry) return;
  client.requests.delete(id);
  post(client, { type: "response", id, ok: !error, ...(error ? { error } : { value }) });
}
async function update(job) {
  const waiting = pendingRequests().filter(entry => entry.job === job);
  if (!waiting.length) return;
  const connection = config;
  try {
    const value = await request(`/slack/jobs/${job}`);
    if (["queued", "running"].includes(value.status)) return;
    const answer = value.status === "ready" ? { job, answer: value.answer }
      : value.status === "failed" && value.error ? { job, error: value.error } : { skip: true };
    for (const entry of waiting) finish(entry, answer);
  } catch (error) {
    // A reconnect takes a fresh snapshot; never replay the original run request.
    if (config.error || config !== connection) return;
    for (const entry of waiting) finish(entry, undefined, error.message);
  }
}
function connect() {
  if (unsubscribe) return;
  unsubscribe = subscribe(value => {
    if (value.type === "settings") {
      const settings = value.hooks?.slack;
      if (!Array.isArray(settings?.keywords) || !settings.keywords.every(k => typeof k === "string" && /^\S{1,40}$/.test(k))) throw new Error("Invalid Slack settings");
      config = { keywords: settings.keywords }; publish();
      for (const job of new Set(pendingRequests().map(entry => entry.job).filter(Boolean))) void update(job);
    } else if (value.type === "job" && value.hook === "slack" && /^[a-f0-9]{64}$/.test(value.job)) void update(value.job);
  }, error => {
    config = { ...config, error }; publish();
  });
}
function cancelJob(job) {
  if (!pendingRequests().some(entry => entry.job === job)) void request("/slack/cancel", { job }).catch(() => {});
}
function cancel(client, id) {
  const entry = client.requests.get(id);
  if (!entry) return;
  client.requests.delete(id);
  if (entry.job) cancelJob(entry.job);
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
  const entry = { client, id: message.id, job: null };
  client.requests.set(message.id, entry);
  try {
    const { action, payload } = message;
    if (!["run", "claim", "delivered"].includes(action) || action !== "run" && !/^[a-f0-9]{64}$/.test(payload?.job)) throw new Error("Invalid Slack operation");
    const value = await request(`/slack/${action}`, payload);
    if (action !== "run") { finish(entry, value); return; }
    if (!/^[a-f0-9]{64}$/.test(value.job)) throw new Error("Invalid bridge job");
    entry.job = value.job;
    if (client.requests.get(message.id) !== entry) { cancelJob(entry.job); return; }
    // Snapshot closes the race where completion arrived before the run response.
    void update(entry.job);
  } catch (error) { finish(entry, undefined, error.message || "Bridge request failed."); }
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
    if (!clients.size) { unsubscribe?.(); unsubscribe = undefined; }
    else for (const target of clients) if (target.popup) post(target, popupStatus());
  });
  post(client, popup ? popupStatus() : { type: "settings", settings: config });
  void connect();
}
