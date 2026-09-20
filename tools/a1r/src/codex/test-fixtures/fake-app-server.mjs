import { appendFileSync, existsSync, writeFileSync } from "node:fs";
import readline from "node:readline";

const scenario = process.env.A1R_FAKE_SCENARIO ?? "normal";
const marker = process.env.A1R_FAKE_MARKER;
const log = process.env.A1R_FAKE_LOG;
const envLog = process.env.A1R_FAKE_ENV_LOG;
const lines = readline.createInterface({ input: process.stdin });

if (envLog) writeFileSync(envLog, JSON.stringify({
  CODEX_HOME: process.env.CODEX_HOME ?? null,
  CODEX_SQLITE_HOME: process.env.CODEX_SQLITE_HOME ?? null,
  CODEX_ACCESS_TOKEN: process.env.CODEX_ACCESS_TOKEN ?? null,
  OPENAI_API_KEY: process.env.OPENAI_API_KEY ?? null,
}));

const send = (message) => process.stdout.write(`${JSON.stringify(message)}\n`);
const record = (method, params) => {
  if (log) appendFileSync(log, `${JSON.stringify({ method, params })}\n`);
};
const allowedLimits = {
  ordinaryUsageAllowed: true,
  rateLimits: {
    limitId: "codex",
    limitName: "Codex",
    primary: { usedPercent: 22, windowDurationMins: 300, resetsAt: 1893456000 },
    secondary: null,
    planType: "plus",
    rateLimitReachedType: null,
  },
  rateLimitsByLimitId: null,
};

function completeTurn(threadId, turnId) {
  send({ method: "item/started", params: {
    threadId, turnId, startedAtMs: Date.now(),
    item: { type: "commandExecution", id: "tool-1", command: "pwd", cwd: process.cwd(), status: "inProgress" },
  } });
  send({ method: "item/completed", params: {
    threadId, turnId, completedAtMs: Date.now(),
    item: { type: "commandExecution", id: "tool-1", command: "pwd", cwd: process.cwd(), status: "completed", exitCode: 0 },
  } });
  send({ method: "item/agentMessage/delta", params: { threadId, turnId, itemId: "message-1", delta: "Hello from Codex." } });
  send({ method: "turn/completed", params: {
    threadId,
    turn: { id: turnId, status: "completed", items: [], itemsView: "full", error: null },
  } });
}

lines.on("line", (line) => {
  const message = JSON.parse(line);
  const { id, method, params = {} } = message;
  record(method, params);
  if (method === "initialized") return;
  if (method === "initialize") {
    send({ id, result: { userAgent: "fake-codex", platformFamily: "unix", platformOs: "test" } });
    return;
  }
  if (method === "account/read") {
    if (scenario === "expired" || scenario.startsWith("login")) {
      send({ id, result: { account: null, requiresOpenaiAuth: true } });
    } else {
      send({ id, result: { account: { type: "chatgpt", email: "fake@example.test", planType: "plus" }, requiresOpenaiAuth: true } });
    }
    return;
  }
  if (method === "account/rateLimits/read") {
    if (scenario === "missing-rate-limits") {
      send({ id, error: { code: -32601, message: "unsupported fake method: account/rateLimits/read" } });
    } else if (scenario === "exhausted") {
      send({ id, result: {
        ...allowedLimits,
        ordinaryUsageAllowed: false,
        rateLimits: { ...allowedLimits.rateLimits, rateLimitReachedType: "rate_limit_reached", primary: { ...allowedLimits.rateLimits.primary, usedPercent: 100 } },
      } });
    } else send({ id, result: allowedLimits });
    return;
  }
  if (method === "account/login/start") {
    const loginId = "login-1";
    if (params.type === "chatgpt") {
      if (Object.keys(params).length !== 1) {
        send({ id, error: { code: -32602, message: "local browser login parameters required" } });
        return;
      }
      if (scenario === "device-response") {
        send({ id, result: { type: "chatgptDeviceCode", loginId, verificationUrl: "https://auth.openai.com/codex/device", userCode: "A1R-TEST" } });
        return;
      }
      send({ id, result: { type: "chatgpt", loginId, authUrl: "https://auth.openai.com/fake" } });
    } else if (params.type === "chatgptDeviceCode") {
      if (Object.keys(params).length !== 1) {
        send({ id, error: { code: -32602, message: "headless login parameters required" } });
        return;
      }
      if (scenario === "browser-response") {
        send({ id, result: { type: "chatgpt", loginId, authUrl: "https://auth.openai.com/fake" } });
        return;
      }
      send({ id, result: { type: "chatgptDeviceCode", loginId, verificationUrl: "https://auth.openai.com/codex/device", userCode: "A1R-TEST" } });
    } else {
      send({ id, error: { code: -32602, message: "unsupported login type" } });
      return;
    }
    if (scenario === "login-pending") return;
    const loginError = scenario === "login-failed"
      ? "ChatGPT sign-in failed"
      : scenario === "login-expired" ? "The one-time code expired"
        : scenario === "login-cancelled" ? "ChatGPT sign-in was cancelled" : null;
    setTimeout(() => send({ method: "account/login/completed", params: {
      loginId,
      success: loginError === null,
      error: loginError,
    } }), 10);
    return;
  }
  if (method === "account/login/cancel") {
    send({ id, result: {} });
    setTimeout(() => send({ method: "account/login/completed", params: {
      loginId: params.loginId,
      success: false,
      error: "ChatGPT sign-in was cancelled",
    } }), 1);
    return;
  }
  if (method === "thread/start") {
    send({ id, result: { thread: { id: "thread-1" }, model: "fake", modelProvider: "openai", cwd: params.cwd } });
    return;
  }
  if (method === "thread/resume") {
    if (scenario === "missing-thread") {
      send({ id, error: { code: -32000, message: "thread not found in this Codex profile" } });
      return;
    }
    send({ id, result: { thread: { id: params.threadId }, model: "fake", modelProvider: "openai", cwd: params.cwd } });
    return;
  }
  if (method === "turn/start") {
    if (scenario === "reconnect" && marker && !existsSync(marker)) {
      writeFileSync(marker, "restarted\n");
      process.exit(23);
    }
    const turnId = "turn-1";
    send({ id, result: { turn: { id: turnId, status: "inProgress", items: [], itemsView: "full", error: null } } });
    if (scenario !== "cancel") setTimeout(() => completeTurn(params.threadId, turnId), 5);
    return;
  }
  if (method === "turn/interrupt") {
    send({ id, result: {} });
    send({ method: "turn/completed", params: {
      threadId: params.threadId,
      turn: { id: params.turnId, status: "interrupted", items: [], itemsView: "full", error: null },
    } });
    return;
  }
  send({ id, error: { code: -32601, message: `unsupported fake method: ${method}` } });
});

process.on("SIGTERM", () => process.exit(0));
