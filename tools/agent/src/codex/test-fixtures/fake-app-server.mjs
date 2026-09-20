import { appendFileSync, existsSync, writeFileSync } from "node:fs";
import readline from "node:readline";

const scenario = process.env.AGENT_FAKE_SCENARIO ?? "normal";
const marker = process.env.AGENT_FAKE_MARKER;
const log = process.env.AGENT_FAKE_LOG;
const artifactPath = process.env.AGENT_FAKE_ARTIFACT;
let threadCounter = 0;
let turnCounter = 0;

if (process.env.AGENT_FAKE_ENV_LOG) writeFileSync(process.env.AGENT_FAKE_ENV_LOG, JSON.stringify({
  CODEX_HOME: process.env.CODEX_HOME ?? null,
  CODEX_SQLITE_HOME: process.env.CODEX_SQLITE_HOME ?? null,
  CODEX_ACCESS_TOKEN: process.env.CODEX_ACCESS_TOKEN ?? null,
  OPENAI_API_KEY: process.env.OPENAI_API_KEY ?? null,
}));

const send = (message) => process.stdout.write(`${JSON.stringify(message)}\n`);
const reply = (id, result = {}) => send({ id, result });
const fail = (id, message) => send({ id, error: { code: -32601, message } });
const notify = (method, params) => send({ method, params });
const record = (method, params) => {
  if (log) appendFileSync(log, `${JSON.stringify({ method, params })}\n`);
};
function completeTurn(threadId, turnId) {
  if (scenario === "image" && artifactPath) {
    notify("item/started", { threadId, turnId, item: { type: "imageGeneration", id: "image-1" } });
    notify("item/completed", { threadId, turnId, item: { type: "imageGeneration", id: "image-1", savedPath: artifactPath } });
  }
  notify("item/started", { threadId, turnId, item: { type: "commandExecution", id: "tool-1" } });
  notify("item/completed", { threadId, turnId, item: { type: "commandExecution", id: "tool-1", exitCode: 0 } });
  notify("item/agentMessage/delta", { threadId, turnId, delta: "Hello from Codex." });
  notify("turn/completed", { threadId, turn: { id: turnId, status: "completed" } });
}

readline.createInterface({ input: process.stdin }).on("line", (line) => {
  const { id, method, params = {} } = JSON.parse(line);
  record(method, params);
  if (method === "initialized") return;
  if (method === "initialize") return reply(id);
  if (method === "account/read") {
    const connected = scenario !== "expired" && !scenario.startsWith("login");
    return reply(id, { account: connected ? { type: "chatgpt", planType: "plus" } : null });
  }
  if (method === "account/login/start") {
    const loginId = "login-1";
    const browser = params.type === "chatgpt";
    if (scenario === "device-response" || (!browser && scenario !== "browser-response")) {
      reply(id, { type: "chatgptDeviceCode", loginId, verificationUrl: "https://auth.openai.com/codex/device", userCode: "Agent-TEST" });
    } else {
      reply(id, { type: "chatgpt", loginId, authUrl: "https://auth.openai.com/fake" });
    }
    if (scenario === "login-pending") return;
    const error = scenario === "login-failed" ? "ChatGPT sign-in failed"
      : scenario === "login-expired" ? "The one-time code expired"
        : scenario === "login-cancelled" ? "ChatGPT sign-in was cancelled" : null;
    setTimeout(() => notify("account/login/completed", { loginId, success: !error, error }), 10);
    return;
  }
  if (method === "account/login/cancel") {
    reply(id);
    return setTimeout(() => notify("account/login/completed", {
      loginId: params.loginId, success: false, error: "ChatGPT sign-in was cancelled",
    }), 1);
  }
  if (method === "thread/start") return reply(id, { thread: { id: `thread-${++threadCounter}` } });
  if (method === "thread/resume") {
    return scenario === "missing-thread"
      ? fail(id, "thread not found in this Codex profile")
      : reply(id, { thread: { id: params.threadId } });
  }
  if (method === "turn/start") {
    if (scenario === "expired") return fail(id, "unauthorized: ChatGPT login expired");
    if (scenario === "exhausted") return fail(id, "Codex allowance usage limit reached");
    if (scenario === "reconnect" && marker && !existsSync(marker)) {
      writeFileSync(marker, "restarted\n");
      process.exit(23);
    }
    const turnId = `turn-${++turnCounter}`;
    reply(id, { turn: { id: turnId } });
    if (scenario !== "cancel") setTimeout(() => completeTurn(params.threadId, turnId), 5);
    return;
  }
  if (method === "turn/interrupt") {
    reply(id);
    return notify("turn/completed", { threadId: params.threadId, turn: { id: params.turnId, status: "interrupted" } });
  }
  if (method === "thread/realtime/start") {
    reply(id);
    notify("thread/realtime/sdp", { threadId: params.threadId, sdp: "fake-answer" });
    return setTimeout(() => notify("thread/realtime/transcript/done", {
      threadId: params.threadId, role: "user", text: "Hello from Codex.",
    }), 5);
  }
  if (method === "thread/realtime/stop") return reply(id);
  fail(id, `unsupported fake method: ${method}`);
});

process.on("SIGTERM", () => process.exit(0));
