/* Slack owns authentication. Only message context and answers cross the extension boundary. */
(() => {
  "use strict";
  const page = window;
  page.agentHooks?.dispose?.();
  const state = { running: false, connected: false, received: 0, replies: 0, pending: 0, error: null, standby: false };
  let settings = { keywords: [] };
  let session, waiting, retry, disposed = false;
  const pending = new Map();

  function emit(type, payload) {
    page.postMessage({ source: "browser-hooks-slack", type, ...payload }, page.location.origin);
  }
  function publishStatus() {
    emit("status", { status: { ...state } });
  }
  function failure(message) { return Object.assign(new Error(message), { publicMessage: message }); }
  function errorMessage(error) { return error?.publicMessage || "Request failed. Run browser-hooks status on your computer."; }
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
      const timer = action === "wait" ? undefined : page.setTimeout(cancel, 20000);
      pending.set(id, {
        resolve(value) { page.clearTimeout(timer); s.abort.signal.removeEventListener("abort", cancel); resolve(value); },
        reject(message) { page.clearTimeout(timer); s.abort.signal.removeEventListener("abort", cancel); reject(failure(typeof message === "string" ? message.slice(0, 500) : "Local bridge request failed. Run browser-hooks status.")); },
      });
      emit("request", { id, action, payload });
    });
  }
  async function reaction(s, event, name) {
    try { await api(s, "reactions.add", { channel: event.channel, timestamp: event.ts, name }); }
    catch { /* Reactions must not prevent command execution or delivery. */ }
  }
  async function history(s, event, after) {
    if (!event.thread_ts || event.thread_ts === event.ts) return [];
    if (after && Number(after) >= Number(event.ts)) return [];
    const messages = new Map(), visited = new Set();
    let cursor = "";
    do {
      const result = await api(s, "conversations.replies", {
        channel: event.channel, ts: event.thread_ts, latest: event.ts, inclusive: "true", limit: "200",
        ...(after ? { oldest: after } : {}), ...(cursor ? { cursor } : {}),
      });
      for (const m of result.messages || []) {
        if (typeof m.ts === "string" && Number(m.ts) <= Number(event.ts) && (!after || Number(m.ts) > Number(after))) {
          messages.set(m.ts, { ts: m.ts, user: m.user || m.bot_id || "unknown", text: (m.text || "").slice(0, 12000) });
        }
      }
      cursor = result.response_metadata?.next_cursor || "";
      if (messages.size > 1000 || visited.has(cursor) && cursor) throw failure("Thread too large. Start a new thread.");
      visited.add(cursor);
    } while (cursor);
    return [...messages.values()].sort((a, b) => Number(a.ts) - Number(b.ts));
  }
  function accepts(event, s) {
    if (!current(s) || event.type !== "message" || event.user !== s.user
      || event.subtype && event.subtype !== "thread_broadcast" || event.bot_id || event.app_id
      || !/^[CDG][A-Z0-9]+$/.test(event.channel || "") || !/^\d+\.\d+$/.test(event.ts || "")
      || Number(event.ts) < s.started || typeof event.text !== "string" || event.text.length > 12000
      || s.sent.has(event.client_msg_id) || s.seen.has(`${event.channel}:${event.ts}`)) return false;
    const match = event.text.match(/^(\S+)\s+([\s\S]*\S)\s*$/);
    return !!match && settings.keywords.includes(match[1].toLowerCase());
  }
  async function deliver(s, event, job) {
    const result = await bridge(s, "wait", { job });
    assertCurrent(s);
    if (result.skip) return;
    const diagnostic = result.error?.message;
    if (diagnostic) result.answer = `⚠️ ${diagnostic}`;
    if (typeof result.answer !== "string" || !result.answer.trim() || result.answer.length > 12000) throw failure("Command returned an invalid answer.");
    // Claim delivery durably before the non-idempotent Slack request. Unknown sends are never retried.
    if (!(await bridge(s, "claim", { job: result.job })).claimed) return;
    assertCurrent(s);
    const clientId = page.crypto.randomUUID();
    s.sent.add(clientId);
    const posted = await api(s, "chat.postMessage", {
      channel: event.channel, thread_ts: event.thread_ts || event.ts, markdown_text: result.answer,
      client_msg_id: clientId, unfurl_links: "false", unfurl_media: "false",
    });
    s.seen.add(`${event.channel}:${posted.ts}`);
    await bridge(s, "delivered", { job: result.job, ts: posted.ts });
    state.replies++;
    await reaction(s, { channel: event.channel, ts: posted.ts }, "robot_face");
    state.error = diagnostic || null;
  }
  function stopKey(event) {
    const keyword = event.text?.match(/^\S+/)?.[0].toLowerCase();
    return keyword ? `${event.channel}:${event.thread_ts || event.ts}:${keyword}` : null;
  }
  function track(s, event, admit, stop = false) {
    state.pending++;
    const key = `${event.channel}:${event.thread_ts || event.ts}`;
    // Persist requests without waiting for earlier agent turns; serialize Slack delivery.
    let job;
    const stopped = () => Number(event.ts) < (s.stops.get(stopKey(event)) || 0);
    const accepted = (s.admissions.get(key) || Promise.resolve()).then(async () => {
      if (stopped()) return;
      job = await admit(stopped); if (job) s.jobs.add(job); return job;
    });
    const admission = accepted.then(() => {}, () => {});
    s.admissions.set(key, admission);
    void admission.then(() => { if (s.admissions.get(key) === admission) s.admissions.delete(key); });
    const work = (!stop && s.threads.get(key) || Promise.resolve()).then(async () => { const job = await accepted; if (job) await deliver(s, event, job); })
      .catch(error => { if (current(s)) state.error = errorMessage(error); })
      .finally(() => {
        s.jobs.delete(job);
        if (session === s) state.pending--;
        if (s.threads.get(key) === work) s.threads.delete(key);
        publishStatus();
      });
    if (!stop) s.threads.set(key, work);
    publishStatus();
  }
  async function recover(s) {
    try {
      const result = await bridge(s, "recover", { team: s.team, user: s.user });
      assertCurrent(s);
      for (const { job, event, stop } of result.jobs) {
        const key = `${event.channel}:${event.ts}`;
        if (s.jobs.has(job)) continue;
        s.jobs.add(job);
        s.seen.add(key);
        track(s, event, () => job, stop);
      }
    } catch (error) { if (current(s)) { state.error = errorMessage(error); publishStatus(); } }
  }
  function receive(s, event) {
    sync();
    if (!accepts(event, s)) return;
    s.seen.add(`${event.channel}:${event.ts}`);
    const stop = /^\S+\s+stop\s*$/i.test(event.text);
    if (!stop && state.pending >= 100) { state.error = "Queue full. Send the command again later."; publishStatus(); return; }
    if (stop) {
      const key = stopKey(event);
      s.stops.set(key, Math.max(s.stops.get(key) || 0, Number(event.ts)));
    }
    state.received++;
    const acknowledged = reaction(s, event, "eyes");
    track(s, event, async stopped => {
      await acknowledged;
      if (stopped()) return;
      const payload = {
        team: s.team, user: s.user, channel: event.channel, ts: event.ts,
        thread_ts: event.thread_ts || event.ts, text: event.text, messages: [],
      };
      const after = !stop && payload.thread_ts !== event.ts ? (await bridge(s, "history", payload)).after : null;
      const messages = stop || stopped() ? [] : await history(s, event, after);
      if (stopped()) return;
      return (await bridge(s, "run", { ...payload, messages, history_after: after })).job;
    }, stop);
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
          page.clearTimeout(s.helloTimeout); s.attempts = 0; state.connected = true; state.error = null; publishStatus();
        } else if (event.type === "reconnect_url") { /* Always reconnect to the fixed Slack origin. */ }
        else if (event.type === "goodbye") socket.close();
        else receive(s, event);
      };
      socket.onerror = () => { if (current(s)) { state.error = "Slack disconnected; reconnecting"; publishStatus(); socket.close(); } };
      socket.onclose = () => {
        page.clearInterval(s.heartbeat); page.clearTimeout(s.helloTimeout);
        if (current(s)) {
          state.connected = false; publishStatus();
          s.reconnect = page.setTimeout(() => connect(s), Math.min(30000, 1000 * 2 ** Math.min(5, s.attempts++)));
        }
      };
      s.helloTimeout = page.setTimeout(() => socket.close(), 20000);
      s.heartbeat = page.setInterval(() => { if (socket.readyState === 1) socket.send(JSON.stringify({ type: "ping", id: ++s.sequence })); }, 15000);
    } catch (error) {
      if (current(s)) { state.error = errorMessage(error); publishStatus(); s.reconnect = page.setTimeout(() => connect(s), 10000); }
    }
  }
  function end() {
    page.clearTimeout(retry); retry = undefined;
    waiting?.abort.abort(); waiting = null;
    if (session) {
      const old = session; session = null;
      old.abort.abort(); disconnect(old); old.release?.();
    }
    state.running = state.connected = state.standby = false; state.pending = 0;
  }
  function attach(auth) {
    if (!page.navigator.locks) { state.error = "This browser needs Web Locks support."; publishStatus(); return; }
    const candidate = waiting = { ...auth, abort: new AbortController() };
    state.standby = true; publishStatus();
    // Queue once. The browser grants ownership immediately when the leader releases it.
    void page.navigator.locks.request(`browser-hooks-slack:${auth.team}`, { signal: candidate.abort.signal }, async () => {
      if (disposed || candidate.abort.signal.aborted || !settings.keywords.length
        || credential()?.team !== auth.team || credential()?.token !== auth.token) return;
      const s = session = { ...auth, abort: candidate.abort, started: Date.now() / 1000,
        seen: new Set(), sent: new Set(), jobs: new Set(), threads: new Map(), admissions: new Map(), stops: new Map(), attempts: 0, sequence: 0 };
      const held = new Promise(resolve => { s.release = resolve; });
      state.running = true; state.standby = false; state.error = null; publishStatus();
      try {
        const identity = await api(s, "auth.test");
        if (identity.bot_id || !identity.user_id) throw failure("A signed-in human Slack account is required.");
        s.user = identity.user_id;
        s.gateway = (await api(s, "team.info")).team.id;
        await recover(s);
        await connect(s);
        await held;
      } catch (error) {
        if (session === s) {
          end(); state.error = errorMessage(error); publishStatus();
          retry = page.setTimeout(() => { retry = undefined; sync(); }, 10000);
        }
      }
    }).catch(error => {
      if (!candidate.abort.signal.aborted && !disposed) { state.error = errorMessage(error); publishStatus(); }
    }).finally(() => { if (waiting === candidate) waiting = null; });
  }
  function sync() {
    if (disposed) return;
    const auth = credential();
    const attached = session || waiting;
    if (attached && (!auth || attached.token !== auth.token || attached.team !== auth.team)) end();
    if (!settings.keywords.length) { end(); publishStatus(); return; }
    if (!session && !waiting && auth && !retry) attach(auth);
  }
  function configure(value) {
    const keywords = [...new Set((value.keywords || []).map(k => String(k).toLowerCase()))];
    if (!keywords.every(k => k.length <= 40 && /^\S+$/.test(k))) throw failure("Keywords must be nonempty words.");
    const next = { keywords, error: value.error || null };
    if (JSON.stringify(next) === JSON.stringify(settings)) return;
    const changed = JSON.stringify(keywords) !== JSON.stringify(settings.keywords);
    const reconnected = settings.error && !next.error;
    if (changed) end();
    settings = next; state.error = next.error;
    if (changed) sync();
    else if (reconnected && session?.user) void recover(session);
    publishStatus();
  }
  function onMessage(event) {
    if (event.source !== page || event.origin !== page.location.origin || event.data?.source !== "browser-hooks-extension") return;
    const data = event.data;
    if (data.type === "configure") { try { configure(data.settings); } catch { state.error = "Invalid hook settings."; publishStatus(); } }
    if (data.type === "response") {
      const entry = pending.get(data.id); if (!entry) return;
      pending.delete(data.id); data.ok ? entry.resolve(data.value) : entry.reject(data.error);
    }
  }
  function dispose() {
    disposed = true; end();
    for (const cleanup of watchers) cleanup();
    page.removeEventListener("message", onMessage); page.removeEventListener("pagehide", dispose);
  }
  page.addEventListener("message", onMessage);
  page.addEventListener("pagehide", dispose, { once: true });
  const watchers = [];
  function watch(target, event, callback) {
    target?.addEventListener(event, callback);
    watchers.push(() => target?.removeEventListener(event, callback));
  }
  watch(page, "storage", event => { if (event.key === "localConfig_v2" || event.key === null) sync(); });
  for (const event of ["popstate", "hashchange", "pageshow", "focus", "online"]) watch(page, event, sync);
  watch(page.navigation, "currententrychange", sync);
  // Storage events only fire in other documents. Notify after same-page Slack auth writes too.
  const storage = page.Storage?.prototype;
  for (const name of ["setItem", "removeItem", "clear"]) {
    const original = storage?.[name];
    if (!original) continue;
    const wrapped = function (...args) {
      const result = Reflect.apply(original, this, args);
      if (this === page.localStorage && (name === "clear" || String(args[0]) === "localConfig_v2")) sync();
      return result;
    };
    storage[name] = wrapped;
    watchers.push(() => { if (storage[name] === wrapped) storage[name] = original; });
  }
  page.agentHooks = Object.freeze({ configure, dispose,
    status: () => Object.freeze({ ...state, keywords: [...settings.keywords] }) });
  publishStatus(); emit("ready", {});
})();
