/* Isolated world: Slack credentials never enter the extension. */
(() => {
  if (window.__slackHookRelay) return;
  window.__slackHookRelay = true;
  let port, retry, stopped = false, status = null, attempts = 0;
  const active = new Set();
  function send(type, data) {
    if (!stopped) window.postMessage({ source: "browser-hooks-extension", type, ...data }, window.location.origin);
  }
  function connect() {
    if (stopped || port) return;
    try {
      const current = port = chrome.runtime.connect({ name: "slack" });
      current.onMessage.addListener(data => {
        if (port !== current) return;
        attempts = 0;
        if (data.type === "settings") send("configure", { settings: data.settings });
        if (data.type === "response" && active.delete(data.id)) send("response", data);
      });
      current.onDisconnect.addListener(() => {
        if (port !== current) return;
        port = null;
        for (const id of active) send("response", { id, ok: false, error: "Extension disconnected. Reload this Slack tab." });
        active.clear();
        send("configure", { settings: { keywords: [], error: "Extension disconnected. Reconnecting automatically…" } });
        if (!stopped) retry = setTimeout(connect, Math.min(30000, 1000 * 2 ** Math.min(attempts++, 5)));
      });
      if (status) current.postMessage({ type: "status", status });
    } catch {
      send("configure", { settings: { keywords: [], error: "Extension updated. Reload this Slack tab." } });
    }
  }
  function message(event) {
    if (event.source !== window || event.origin !== window.location.origin || event.data?.source !== "browser-hooks-slack") return;
    const data = event.data;
    if (data.type === "ready") { if (port) port.postMessage({ type: "ready" }); else connect(); }
    if (data.type === "status") { status = data.status; port?.postMessage({ type: "status", status }); }
    if (data.type === "request" && typeof data.id === "string" && data.id.length <= 100 && !active.has(data.id)
      && active.size < 128 && ["run", "wait", "recover", "history", "claim", "delivered"].includes(data.action)) {
      if (!port) { send("response", { id: data.id, ok: false, error: "Extension disconnected. Reload this Slack tab." }); return; }
      active.add(data.id);
      port.postMessage({ type: "request", id: data.id, action: data.action, payload: data.payload });
    }
    if (data.type === "cancel" && active.delete(data.id)) port?.postMessage({ type: "cancel", id: data.id });
  }
  window.addEventListener("message", message);
  window.addEventListener("pagehide", () => {
    stopped = true; clearTimeout(retry); window.removeEventListener("message", message);
    port?.disconnect(); active.clear();
  }, { once: true });
  connect();
})();
