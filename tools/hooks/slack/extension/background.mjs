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

function slackSender(sender) {
  if (!sender.tab || sender.frameId !== 0 || !sender.url) return false;
  const url = new URL(sender.url);
  return url.origin === "https://app.slack.com";
}

export async function handle(message, sender) {
  if (!message || typeof message !== "object") throw new Error("Invalid message");
  if (slackSender(sender)) {
    if (message.type === "slack.settings") return settings();
    if (message.type !== "slack.request") throw new Error("Unknown Slack operation");
    const { action, payload } = message;
    if (action === "run") return request("/run", payload);
    if (action === "poll" && /^[a-f0-9]{64}$/.test(payload?.job)) return request(`/jobs/${payload.job}`);
    if (["claim", "delivered", "cancel"].includes(action) && /^[a-f0-9]{64}$/.test(payload?.job)) return request(`/${action}`, payload);
    throw new Error("Invalid Slack operation");
  }
  const ownPage = sender.url?.startsWith(chrome.runtime.getURL("popup/"));
  if (!ownPage || sender.tab) throw new Error("Only the extension popup can read bridge status");
  if (message.type === "popup.settings") return settings();
  throw new Error("Unknown popup operation");
}

chrome.runtime.onMessage.addListener((message, sender, reply) => {
  handle(message, sender).then(value => reply({ ok: true, value }), error => reply({ ok: false, error: error.message || "Bridge request failed." }));
  return true;
});

// Loading the extension is enough to establish the initial trust; no popup action.
void settings();
