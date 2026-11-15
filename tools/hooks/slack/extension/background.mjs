const BASE = "http://127.0.0.1:19736";
const trusted = chrome.storage.local.setAccessLevel({ accessLevel: "TRUSTED_CONTEXTS" });

async function request(path, body, pairing = false) {
  await trusted;
  const { bridgeToken } = await chrome.storage.local.get("bridgeToken");
  if (!pairing && !bridgeToken) throw new Error("Pair the local bridge in Browser Hooks.");
  let response;
  try { response = await fetch(`${BASE}${path}`, {
    method: body === undefined ? "GET" : "POST", credentials: "omit", redirect: "error", cache: "no-store",
    signal: AbortSignal.timeout(8000),
    headers: { "Content-Type": "application/json", "X-Browser-Hooks-Origin": chrome.runtime.getURL("").replace(/\/$/, ""),
      ...(!pairing ? { Authorization: `Bearer ${bridgeToken}` } : {}) },
    ...(body === undefined ? {} : { body: JSON.stringify(body) }),
  }); } catch { throw new Error("Local bridge is not running. Rerun the Slack browser installer."); }
  if (response.status === 403) throw new Error(pairing
    ? "Pairing code expired or incorrect. Rerun the installer and copy the new code."
    : "Browser pairing expired. Rerun the installer and pair Browser Hooks again.");
  if (!response.ok) throw new Error("Local bridge rejected the request. Run slack-hook status on your computer.");
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
  if (!ownPage || sender.tab) throw new Error("Only the extension popup can configure the bridge");
  if (message.type === "popup.settings") return settings();
  if (message.type === "popup.pair") {
    if (typeof message.code !== "string" || !/^[A-Za-z0-9_-]{20,100}$/.test(message.code)) throw new Error("Enter the pairing code printed by the installer.");
    const paired = await request("/pair", { code: message.code }, true);
    if (typeof paired.token !== "string" || !/^[A-Za-z0-9_-]{40,100}$/.test(paired.token)) throw new Error("Invalid bridge pairing response");
    await chrome.storage.local.set({ bridgeToken: paired.token });
    return settings();
  }
  throw new Error("Unknown popup operation");
}

chrome.runtime.onMessage.addListener((message, sender, reply) => {
  handle(message, sender).then(value => reply({ ok: true, value }), error => reply({ ok: false, error: error.message || "Bridge request failed." }));
  return true;
});
