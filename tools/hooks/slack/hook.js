/* Run inside the signed-in Slack page. Credentials never leave this page. */
(() => {
  "use strict";
  const page = window;
  page.agentHooks?.stop();
  const keyword = "hook";
  const started = Date.now() / 1000;
  const seen = new Set();
  const sent = new Set();
  const threads = new Map();
  const state = { running: true, connected: false, received: 0, replies: 0, error: null };
  let socket, reconnect, heartbeat, badge, identity, channel, gateway;
  let attempts = 0;
  let sequence = 0;
  let handler = async ({ text }) => `🤖 Browser hook received: ${text}`;

  function render() {
    if (badge) badge.firstChild.textContent = state.error ? "Hook error · "
      : `Hook ${state.connected ? "listening" : "connecting"} · ${state.replies} replies · `;
  }

  function fail(message) {
    state.error = message;
    render();
    console.warn(`[Agent Hooks] ${message}`);
  }

  function token() {
    const team = page.location.pathname.match(/^\/client\/([A-Z0-9]+)\//)?.[1];
    const config = JSON.parse(page.localStorage.getItem("localConfig_v2") || "{}");
    const value = config.teams?.[team]?.token;
    if (typeof value !== "string" || !value.startsWith("xoxc-")) {
      throw new Error("No Slack web session found in this tab. Sign in and run the hook again.");
    }
    return value;
  }

  async function api(method, values = {}) {
    const response = await page.fetch(`/api/${method}`, {
      method: "POST", credentials: "include", redirect: "error",
      body: new URLSearchParams({ token: token(), ...values }),
    });
    if (!response.ok) throw new Error(`Slack request failed (HTTP ${response.status}).`);
    const result = await response.json();
    if (!result.ok) {
      const code = /^[a-z_]+$/.test(result.error) ? result.error : "unknown_error";
      throw new Error(`Slack ${method}: ${code}`);
    }
    return result;
  }

  function stop() {
    state.running = false;
    state.connected = false;
    page.clearTimeout(reconnect);
    page.clearInterval(heartbeat);
    socket?.close();
    badge?.remove();
    page.removeEventListener("pagehide", stop);
    console.info("[Agent Hooks] Stopped.");
  }

  function accepts(event) {
    return state.running && event.type === "message" && event.channel === channel
      && event.user === identity && !event.subtype && !event.bot_id && !event.app_id
      && typeof event.ts === "string" && Number(event.ts) >= started
      && typeof event.text === "string" && event.text.toLowerCase().startsWith(`${keyword} `)
      && event.text.slice(keyword.length).trim() && !seen.has(event.ts);
  }

  async function reply(event) {
    if (!state.running) return;
    const answer = await handler(Object.freeze({
      text: event.text.slice(keyword.length).trim(), channel,
      threadTs: event.thread_ts || event.ts, messageTs: event.ts,
    }));
    if (!state.running) return;
    if (typeof answer !== "string" || !answer.trim() || answer.length > 12000) {
      throw new Error("Hook handler must return an answer between 1 and 12,000 characters.");
    }
    const clientId = page.crypto.randomUUID();
    sent.add(clientId);
    const result = await api("chat.postMessage", {
      channel, thread_ts: event.thread_ts || event.ts, text: answer,
      client_msg_id: clientId,
      unfurl_links: "false", unfurl_media: "false",
    });
    seen.add(result.ts);
    state.replies++;
    state.error = null;
    render();
  }

  function receive(event) {
    if (sent.has(event.client_msg_id) || !accepts(event)) return;
    seen.add(event.ts);
    state.received++;
    const thread = event.thread_ts || event.ts;
    const pending = (threads.get(thread) || Promise.resolve()).then(() => reply(event))
      .catch(error => fail(error.message));
    threads.set(thread, pending);
    void pending.finally(() => { if (threads.get(thread) === pending) threads.delete(thread); });
  }

  async function connect() {
    if (!state.running) return;
    try {
      const auth = await api("auth.test");
      if (auth.user_id !== identity) throw new Error("Slack account changed. Stop and restart the hook.");
      if (!state.running) return;
      const query = new URLSearchParams({ token: token(), gateway_server: `${gateway}-1`,
        slack_client: "desktop", batch_presence_aware: "1" });
      socket = new page.WebSocket(`wss://wss-primary.slack.com/?${query}`);
      socket.onmessage = ({ data }) => {
        let event;
        try { event = JSON.parse(data); } catch { return; }
        if (event.type === "hello") {
          attempts = 0;
          state.connected = true;
          state.error = null;
          render();
          console.info("[Agent Hooks] Listening in your self-DM. Send: hook ping");
        } else receive(event);
      };
      socket.onerror = () => fail("Slack event connection failed. Reconnecting while this tab stays open.");
      socket.onclose = () => {
        state.connected = false;
        page.clearInterval(heartbeat);
        render();
        if (state.running) reconnect = page.setTimeout(connect, Math.min(30000, 1000 * 2 ** attempts++));
      };
      heartbeat = page.setInterval(() => {
        if (socket.readyState === 1) socket.send(JSON.stringify({ type: "ping", id: ++sequence }));
      }, 15000);
    } catch (error) {
      fail(error.message);
      if (state.running) reconnect = page.setTimeout(connect, 10000);
    }
  }

  async function start() {
    if (page.location.origin !== "https://app.slack.com") throw new Error("Run this hook in the Slack web app.");
    channel = page.location.pathname.match(/^\/client\/[A-Z0-9]+\/(D[A-Z0-9]+)/)?.[1];
    if (!channel) throw new Error("Open your self-DM before starting the hook.");
    const auth = await api("auth.test");
    identity = auth.user_id;
    const info = await api("conversations.info", { channel });
    if (!info.channel?.is_im || info.channel.user !== identity) {
      throw new Error("Open your own self-DM. This hook cannot run in other conversations.");
    }
    gateway = (await api("team.info")).team.id;
    if (!state.running) return;
    badge = page.document.createElement("div");
    badge.style.cssText = "position:fixed;bottom:12px;left:12px;z-index:2147483647;background:#17252b;color:white;padding:8px 12px;border-radius:8px;font:12px system-ui;box-shadow:0 2px 12px #0004";
    badge.append(page.document.createTextNode("Hook connecting · "));
    const button = page.document.createElement("button");
    button.textContent = "Stop";
    button.style.cssText = "border:0;border-radius:4px;padding:3px 7px;cursor:pointer";
    button.addEventListener("click", stop);
    badge.append(button);
    page.document.body.append(badge);
    page.addEventListener("pagehide", stop, { once: true });
    await connect();
  }

  page.agentHooks = Object.freeze({
    stop,
    status: () => Object.freeze({ ...state }),
    setHandler(callback) {
      if (typeof callback !== "function") throw new TypeError("Pass an async function that returns reply text.");
      handler = callback;
    },
  });
  void start().catch(error => { stop(); fail(error.message); });
})();
