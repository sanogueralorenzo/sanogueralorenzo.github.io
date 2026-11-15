/* Slack owns authentication. Only message context and answers cross the extension boundary. */
(() => {
  "use strict";
  const page = window;
  page.agentHooks?.dispose?.();
  const state = { running: false, connected: false, received: 0, replies: 0, pending: 0, error: null, standby: false };
  let settings = { mode: "agent", keywords: [] };
  let session, disposed = false, acquiring = false, retryAt = 0, badge;
  const pending = new Map();

  function emit(type, payload) {
    page.postMessage({ source: "browser-hooks-slack", type, ...payload }, page.location.origin);
  }
  function render() {
    if (!badge && page.document.body) {
      badge = page.document.createElement("aside");
      badge.id = "browser-hooks-slack";
      badge.style.cssText = "position:fixed;bottom:12px;left:12px;z-index:2147483647;background:#17252b;color:white;padding:8px 12px;border-radius:8px;font:12px/1.4 system-ui;max-width:min(520px,calc(100vw - 24px));box-sizing:border-box;overflow-wrap:anywhere;box-shadow:0 2px 12px #0004";
      badge.append(page.document.createTextNode(""));
      page.document.body.append(badge);
    }
    if (!badge) return;
    badge.firstChild.textContent = state.error ? `Hook · ${state.error}`
      : !settings.keywords.length ? "Hook · connect local bridge"
      : state.standby ? "Hook · another tab is listening" : state.connected
        ? `Hook listening (${settings.keywords.join(" / ")}) · ${state.replies} replies` : "Hook connecting…";
    emit("status", { status: { ...state } });
  }
  function failure(message) { return Object.assign(new Error(message), { publicMessage: message }); }
  function errorMessage(error) { return error?.publicMessage || "Request failed. Run slack-hook status on your computer."; }
  function credential() {
    const team = page.location.pathname.match(/^\/client\/([A-Z0-9]+)(?:\/|$)/)?.[1];
    let config;
    try { config = JSON.parse(page.localStorage.getItem("localConfig_v2") || "{}"); } catch { return null; }
    const token = config.teams?.[team]?.token;
    return team && typeof token === "string" && token.startsWith("xoxc-") ? { team, token } : null;
  }
  function current(s) {
    const auth = credential();
    return !disposed && session === s && !s.abort.signal.aborted
      && auth?.team === s.team && auth.token === s.token;
  }
  function assertCurrent(s) {
    if (!current(s)) throw failure("Listener stopped or Slack account changed.");
  }
  async function api(s, method, values = {}) {
    assertCurrent(s);
    const response = await page.fetch(`/api/${method}`, {
      method: "POST", credentials: "same-origin", mode: "same-origin", redirect: "error",
      signal: AbortSignal.any([s.abort.signal, AbortSignal.timeout(20000)]),
      body: new URLSearchParams({ ...values, token: s.token }),
    });
    assertCurrent(s);
    if (!response.ok) throw failure(response.status === 429 ? "Slack rate limited. Try later." : `Slack HTTP ${response.status}.`);
    const result = await response.json();
    if (!result.ok) {
      const messages = {
        invalid_auth: "Slack sign-in expired. Sign in again in this browser.",
        not_authed: "Sign in to Slack in this browser.", token_revoked: "Slack sign-in expired. Sign in again in this browser.",
        channel_not_found: "Slack could not access this conversation. Check your membership.",
        is_archived: "This Slack conversation is archived. Use an active conversation.",
        ratelimited: "Slack rate limited requests. Retry later.",
      };
      throw failure(messages[result.error] || `Slack ${method}: ${/^[a-z_]+$/.test(result.error) ? result.error : "request_failed"}`);
    }
    return result;
  }
  async function bridge(s, action, payload) {
    assertCurrent(s);
    const id = page.crypto.randomUUID();
    return new Promise((resolve, reject) => {
      const cancel = () => { page.clearTimeout(timer); s.abort.signal.removeEventListener("abort", cancel); pending.delete(id); emit("cancel", { id }); reject(failure("Listener stopped.")); };
      s.abort.signal.addEventListener("abort", cancel, { once: true });
      const timer = page.setTimeout(cancel, 660000);
      pending.set(id, {
        resolve(value) { page.clearTimeout(timer); s.abort.signal.removeEventListener("abort", cancel); resolve(value); },
        reject(message) { page.clearTimeout(timer); s.abort.signal.removeEventListener("abort", cancel); reject(failure(typeof message === "string" ? message.slice(0, 500) : "Local bridge request failed. Rerun the installer.")); },
      });
      emit("request", { id, action, payload });
    });
  }
  async function reaction(s, event, name, remove = false) {
    try { await api(s, `reactions.${remove ? "remove" : "add"}`, { channel: event.channel, timestamp: event.ts, name }); }
    catch { /* Reactions must not prevent command execution or delivery. */ }
  }
  async function history(s, event) {
    if (!event.thread_ts || event.thread_ts === event.ts) return [];
    const messages = [], visited = new Set();
    let cursor = "";
    do {
      const result = await api(s, "conversations.replies", {
        channel: event.channel, ts: event.thread_ts, latest: event.ts, inclusive: "true", limit: "200", ...(cursor ? { cursor } : {}),
      });
      for (const m of result.messages || []) {
        if (typeof m.ts === "string" && Number(m.ts) <= Number(event.ts)) messages.push({ ts: m.ts, user: m.user || m.bot_id || "unknown", text: (m.text || "").slice(0, 12000) });
      }
      cursor = result.response_metadata?.next_cursor || "";
      if (messages.length > 1000 || visited.has(cursor) && cursor) throw failure("Thread too large. Start a new thread.");
      visited.add(cursor);
    } while (cursor);
    return messages;
  }
  function parse(event, s) {
    if (!current(s) || event.type !== "message" || event.user !== s.user
      || event.subtype && event.subtype !== "thread_broadcast" || event.bot_id || event.app_id
      || !/^[CDG][A-Z0-9]+$/.test(event.channel || "") || !/^\d+\.\d+$/.test(event.ts || "")
      || Number(event.ts) < s.started || typeof event.text !== "string" || event.text.length > 12000
      || s.sent.has(event.client_msg_id) || s.seen.has(`${event.channel}:${event.ts}`)) return null;
    const match = event.text.match(/^(\S+)\s+([\s\S]*\S)\s*$/);
    if (!match || !settings.keywords.includes(match[1].toLowerCase())) return null;
    return { keyword: match[1].toLowerCase(), text: match[2] };
  }
  async function process(s, event, request) {
    assertCurrent(s);
    try {
      const context = await history(s, event);
      let result;
      if (settings.mode === "echo") result = { answer: `🤖 Browser hook received: ${request.text}` };
      else result = await bridge(s, "run", {
        team: s.team, user: s.user, channel: event.channel, ts: event.ts,
        thread_ts: event.thread_ts || event.ts, text: event.text, messages: context,
      });
      assertCurrent(s);
      if (result.skip) return;
      const diagnostic = result.error?.message;
      if (diagnostic) result.answer = `⚠️ ${diagnostic}`;
      if (typeof result.answer !== "string" || !result.answer.trim() || result.answer.length > 12000) throw failure("Command returned an invalid answer.");
      // Claim delivery durably before the non-idempotent Slack request. Unknown sends are never retried.
      if (settings.mode !== "echo" && !(await bridge(s, "claim", { job: result.job })).claimed) return;
      assertCurrent(s);
      const clientId = page.crypto.randomUUID();
      s.sent.add(clientId);
      const posted = await api(s, "chat.postMessage", {
        channel: event.channel, thread_ts: event.thread_ts || event.ts, markdown_text: result.answer,
        client_msg_id: clientId, unfurl_links: "false", unfurl_media: "false",
      });
      s.seen.add(`${event.channel}:${posted.ts}`);
      if (settings.mode !== "echo") await bridge(s, "delivered", { job: result.job, ts: posted.ts });
      state.replies++;
      await reaction(s, { channel: event.channel, ts: posted.ts }, "robot_face");
      await reaction(s, event, diagnostic ? "warning" : "white_check_mark");
      state.error = diagnostic || null;
    } finally { await reaction(s, event, "eyes", true); }
  }
  function receive(s, event) {
    const request = parse(event, s);
    if (!request) return;
    s.seen.add(`${event.channel}:${event.ts}`);
    if (state.pending >= 100) { state.error = "Queue full. Send the command again later."; render(); return; }
    state.received++; state.pending++;
    const key = `${event.channel}:${event.thread_ts || event.ts}`;
    const acknowledged = reaction(s, event, "eyes");
    const work = (s.threads.get(key) || Promise.resolve()).then(async () => { await acknowledged; return process(s, event, request); })
      .catch(error => { if (current(s)) { state.error = errorMessage(error); void reaction(s, event, "warning"); } })
      .finally(() => {
        if (session === s) state.pending--;
        if (s.threads.get(key) === work) s.threads.delete(key);
        render();
      });
    s.threads.set(key, work); render();
  }
  function disconnect(s) {
    page.clearTimeout(s.reconnect); page.clearInterval(s.heartbeat); page.clearTimeout(s.helloTimeout);
    s.socket?.close();
  }
  async function connect(s) {
    if (!current(s)) return;
    try {
      const auth = await api(s, "auth.test");
      if (auth.user_id !== s.user || auth.bot_id) throw failure("Slack account changed.");
      assertCurrent(s);
      const query = new URLSearchParams({ token: s.token, gateway_server: `${s.gateway}-1`, slack_client: "desktop", batch_presence_aware: "1" });
      const socket = s.socket = new page.WebSocket(`wss://wss-primary.slack.com/?${query}`);
      socket.onmessage = ({ data }) => {
        if (!current(s) || s.socket !== socket) return;
        let event; try { event = JSON.parse(data); } catch { return; }
        if (event.type === "hello") {
          page.clearTimeout(s.helloTimeout); s.attempts = 0; state.connected = true; state.error = null; render();
        } else if (event.type === "reconnect_url") { /* Always reconnect to the fixed Slack origin. */ }
        else if (event.type === "goodbye") socket.close();
        else receive(s, event);
      };
      socket.onerror = () => { if (current(s)) { state.error = "Slack disconnected; reconnecting"; render(); socket.close(); } };
      socket.onclose = () => {
        page.clearInterval(s.heartbeat); page.clearTimeout(s.helloTimeout);
        if (current(s)) {
          state.connected = false; render();
          s.reconnect = page.setTimeout(() => connect(s), Math.min(30000, 1000 * 2 ** Math.min(5, s.attempts++)));
        }
      };
      s.helloTimeout = page.setTimeout(() => socket.close(), 20000);
      s.heartbeat = page.setInterval(() => { if (socket.readyState === 1) socket.send(JSON.stringify({ type: "ping", id: ++s.sequence })); }, 15000);
    } catch (error) {
      if (current(s)) { state.error = errorMessage(error); render(); s.reconnect = page.setTimeout(() => connect(s), 10000); }
    }
  }
  function end() {
    if (session) {
      const old = session; session = null;
      old.abort.abort(); disconnect(old); old.release?.();
    }
    state.running = state.connected = state.standby = false; state.pending = 0;
  }
  async function attach(auth) {
    if (!page.navigator.locks) { state.error = "This browser needs Web Locks support."; render(); return; }
    acquiring = true;
    try {
      await page.navigator.locks.request(`browser-hooks-slack:${auth.team}`, { ifAvailable: true }, async lock => {
        if (!lock) { state.standby = true; render(); return; }
        if (disposed || !settings.keywords.length || credential()?.token !== auth.token) return;
        const s = session = { ...auth, abort: new AbortController(), started: Date.now() / 1000,
          seen: new Set(), sent: new Set(), threads: new Map(), attempts: 0, sequence: 0 };
        const held = new Promise(resolve => { s.release = resolve; });
        state.running = true; state.standby = false; state.error = null; render();
        try {
          const identity = await api(s, "auth.test");
          if (identity.bot_id || !identity.user_id) throw failure("A signed-in human Slack account is required.");
          s.user = identity.user_id;
          s.gateway = (await api(s, "team.info")).team.id;
          await connect(s);
          await held;
        } catch (error) {
          if (session === s) { end(); state.error = errorMessage(error); retryAt = Date.now() + 10000; render(); }
        }
      });
    } finally { acquiring = false; }
  }
  function tick() {
    if (disposed) return;
    const auth = credential();
    if (session && (!auth || session.token !== auth.token || session.team !== auth.team)) end();
    if (!settings.keywords.length) { end(); render(); return; }
    if (!session && !acquiring && auth && Date.now() >= retryAt) void attach(auth);
  }
  function configure(value) {
    const keywords = [...new Set((value.keywords || []).map(k => String(k).toLowerCase()))];
    if (!keywords.every(k => k.length <= 40 && /^\S+$/.test(k))) throw failure("Keywords must be nonempty words.");
    if (!['agent', 'echo'].includes(value.mode)) throw failure("Choose agent or echo mode.");
    const next = { mode: value.mode, keywords };
    if (value.error) { state.error = value.error; render(); }
    if (JSON.stringify(next) === JSON.stringify(settings)) return;
    end(); settings = next; retryAt = 0; state.error = value.error || null; tick(); render();
  }
  function onMessage(event) {
    if (event.source !== page || event.origin !== page.location.origin || event.data?.source !== "browser-hooks-extension") return;
    const data = event.data;
    if (data.type === "configure") { try { configure(data.settings); } catch { state.error = "Invalid hook settings."; render(); } }
    if (data.type === "response") {
      const entry = pending.get(data.id); if (!entry) return;
      pending.delete(data.id); data.ok ? entry.resolve(data.value) : entry.reject(data.error);
    }
  }
  function dispose() {
    disposed = true; end(); page.clearInterval(watch); badge?.remove();
    page.removeEventListener("message", onMessage); page.removeEventListener("pagehide", dispose);
  }
  page.addEventListener("message", onMessage);
  page.addEventListener("pagehide", dispose, { once: true });
  const watch = page.setInterval(tick, 1000);
  page.agentHooks = Object.freeze({ configure, dispose,
    status: () => Object.freeze({ ...state, keywords: [...settings.keywords], mode: settings.mode }) });
  render(); emit("ready", {});
})();
