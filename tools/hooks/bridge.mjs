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

export async function request(path, body) {
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

const subscribers = new Set();
let latest, lastError;
let socket, opening = false, generation = 0, retry, heartbeat, handshake, attempts = 0;

function publish(value) {
  for (const subscriber of subscribers) subscriber.event(value);
  if (value.type === "settings") { latest = value; lastError = undefined; }
}
function failed(error) {
  lastError = error;
  for (const subscriber of subscribers) subscriber.error(error);
}
function stop() {
  generation++; opening = false;
  clearTimeout(retry); clearTimeout(handshake); clearInterval(heartbeat);
  retry = undefined;
  const old = socket; socket = undefined; old?.close();
}
function reconnect() {
  if (!subscribers.size || retry) return;
  retry = setTimeout(() => { retry = undefined; void connect(); }, Math.min(30000, 1000 * 2 ** Math.min(attempts++, 5)));
}
async function connect() {
  if (!subscribers.size || opening || socket) return;
  opening = true;
  const version = generation;
  try {
    await request("/config");
    const { bridgeToken } = await chrome.storage.local.get("bridgeToken");
    if (version !== generation || !subscribers.size) return;
    const stream = socket = new WebSocket("ws://127.0.0.1:19736/events");
    handshake = setTimeout(() => stream.close(), 8000);
    let lastMessage = Date.now();
    stream.onopen = () => { if (socket === stream) stream.send(JSON.stringify({ type: "authenticate", token: bridgeToken })); };
    stream.onmessage = event => {
      if (socket !== stream) return;
      lastMessage = Date.now();
      let value;
      try {
        value = JSON.parse(event.data);
        if (value.type === "settings" && (!value.hooks || typeof value.hooks !== "object" || Array.isArray(value.hooks))) throw new Error();
        publish(value);
      } catch { stream.close(); return; }
      if (value.type === "settings") {
        clearTimeout(handshake); clearInterval(heartbeat); attempts = 0;
        heartbeat = setInterval(() => {
          if (Date.now() - lastMessage > 40000) stream.close();
          else if (stream.readyState === WebSocket.OPEN) stream.send(JSON.stringify({ type: "ping" }));
        }, 20000);
      }
    };
    stream.onerror = () => stream.close();
    stream.onclose = () => {
      if (socket !== stream) return;
      socket = undefined; clearTimeout(handshake); clearInterval(heartbeat);
      failed("Local bridge disconnected. Reconnecting automatically…"); reconnect();
    };
  } catch (error) {
    if (version === generation) { failed(error.message); reconnect(); }
  } finally { if (version === generation) opening = false; }
}
export function subscribe(event, error) {
  const subscriber = { event, error };
  subscribers.add(subscriber);
  if (latest) event(latest);
  if (lastError) error(lastError);
  void connect();
  return () => {
    subscribers.delete(subscriber);
    if (!subscribers.size) stop();
  };
}
