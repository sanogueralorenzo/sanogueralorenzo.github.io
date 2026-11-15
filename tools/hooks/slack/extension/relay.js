/* Isolated world: Slack session credentials are never read or sent to the extension. */
(() => {
  if (window.__slackHookRelay) return;
  window.__slackHookRelay = true;
  const active = new Map();
  let stopped = false, refreshing = false, status = null;
  const pause = ms => new Promise(resolve => setTimeout(resolve, ms));
  function send(type, data) {
    if (!stopped) window.postMessage({ source: "browser-hooks-extension", type, ...data }, window.location.origin);
  }
  async function call(action, payload) {
    const response = await chrome.runtime.sendMessage({ type: "slack.request", action, payload });
    if (!response?.ok) throw new Error("Local bridge request failed.");
    return response.value;
  }
  async function refresh() {
    if (refreshing || stopped) return;
    refreshing = true;
    try {
      const result = await chrome.runtime.sendMessage({ type: "slack.settings" });
      if (result?.ok) send("configure", { settings: result.value });
    } catch { send("configure", { settings: { mode: "agent", keywords: [] } }); }
    finally { refreshing = false; }
  }
  async function dispatch(data) {
    if (active.has(data.id) || active.size >= 100) return;
    const entry = { cancelled: false, job: null };
    active.set(data.id, entry);
    try {
      let result = await call(data.action, data.payload);
      if (data.action === "run") {
        entry.job = result.job;
        const deadline = Date.now() + 650000;
        while (!entry.cancelled && ["queued", "running"].includes(result.status)) {
          if (Date.now() > deadline) throw new Error("Command timed out.");
          await pause(1000);
          result = await call("poll", { job: entry.job });
        }
        if (entry.cancelled) { await call("cancel", { job: entry.job }); return; }
        if (result.status === "ready") result = { job: result.job, answer: result.answer };
        else if (["delivered", "sending", "interrupted", "cancelled"].includes(result.status)) result = { skip: true };
        else throw new Error("Command failed.");
      }
      if (!entry.cancelled) send("response", { id: data.id, ok: true, value: result });
    } catch {
      if (entry.job) void call("cancel", { job: entry.job }).catch(() => {});
      if (!entry.cancelled) send("response", { id: data.id, ok: false });
    } finally { active.delete(data.id); }
  }
  function message(event) {
    if (event.source !== window || event.origin !== window.location.origin || event.data?.source !== "browser-hooks-slack") return;
    const data = event.data;
    if (data.type === "ready") void refresh();
    if (data.type === "status") status = data.status;
    if (data.type === "request" && typeof data.id === "string" && data.id.length <= 100
      && ["run", "claim", "delivered"].includes(data.action)) void dispatch(data);
    if (data.type === "cancel") {
      const entry = active.get(data.id);
      if (entry) { entry.cancelled = true; if (entry.job) void call("cancel", { job: entry.job }).catch(() => {}); }
    }
  }
  chrome.runtime.onMessage.addListener((data, _sender, reply) => {
    if (data?.type === "slack.status") { reply(status); return false; }
  });
  window.addEventListener("message", message);
  const timer = setInterval(refresh, 5000);
  window.addEventListener("pagehide", () => {
    stopped = true; clearInterval(timer); window.removeEventListener("message", message);
    for (const entry of active.values()) { entry.cancelled = true; if (entry.job) void call("cancel", { job: entry.job }).catch(() => {}); }
  }, { once: true });
  void refresh();
})();
