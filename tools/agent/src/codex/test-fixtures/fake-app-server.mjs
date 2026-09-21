import { appendFileSync, existsSync, writeFileSync } from "node:fs";
import readline from "node:readline";

const scenario = process.env.AGENT_FAKE_SCENARIO ?? "normal";
const marker = process.env.AGENT_FAKE_MARKER;
const log = process.env.AGENT_FAKE_LOG;
const artifactPath = process.env.AGENT_FAKE_ARTIFACT;
let threadCounter = 0;
let turnCounter = 0;
let dynamicTurn = null;
let account = scenario === "expired" || scenario.startsWith("login")
  ? null
  : { type: scenario === "api-account" ? "apiKey" : "chatgpt", planType: "plus" };

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
function completeTurn(threadId, turnId, handoff = false) {
  if (scenario.startsWith("context-compaction") && !handoff) {
    notify("item/started", { threadId, turnId, item: { type: "contextCompaction", id: "compact-1" } });
    notify("item/completed", { threadId, turnId, item: { type: "contextCompaction", id: "compact-1" } });
  }
  if (scenario === "image" && artifactPath) {
    notify("item/started", { threadId, turnId, item: { type: "imageGeneration", id: "image-1" } });
    notify("item/completed", { threadId, turnId, item: { type: "imageGeneration", id: "image-1", savedPath: artifactPath } });
  }
  notify("item/started", { threadId, turnId, item: { type: "commandExecution", id: "tool-1" } });
  notify("item/completed", { threadId, turnId, item: { type: "commandExecution", id: "tool-1", exitCode: 0 } });
  notify("item/agentMessage/delta", {
    threadId,
    turnId,
    delta: handoff
      ? "Objective: continue the Agent task. Decisions: keep clients thin. Next: handle the user's pending request."
      : "Hello from Codex.",
  });
  notify("turn/completed", { threadId, turn: { id: turnId, status: "completed" } });
}

readline.createInterface({ input: process.stdin }).on("line", (line) => {
  const { id, method, params = {}, result } = JSON.parse(line);
  if (log) appendFileSync(log, `${JSON.stringify(method
    ? { method, params: params.apiKey ? { ...params, apiKey: "[redacted]" } : params }
    : { id, result })}\n`);
  if (!method && scenario === "session-navigation" && dynamicTurn) {
    if (id === "list-conversations") {
      const conversations = JSON.parse(result?.contentItems?.[0]?.text ?? "[]");
      const sessionId = conversations[0]?.id;
      dynamicTurn.sessionId = sessionId;
      notify("item/completed", {
        threadId: dynamicTurn.threadId,
        turnId: dynamicTurn.turnId,
        item: { type: "dynamicToolCall", id: "list-item", tool: "list_conversations", status: "completed", success: result?.success },
      });
      notify("item/started", {
        threadId: dynamicTurn.threadId,
        turnId: dynamicTurn.turnId,
        item: { type: "dynamicToolCall", id: "read-item", tool: "read_conversation", arguments: { sessionId }, status: "inProgress" },
      });
      return send({
        id: "read-conversation",
        method: "item/tool/call",
        params: { threadId: dynamicTurn.threadId, turnId: dynamicTurn.turnId, callId: "read-item", namespace: null, tool: "read_conversation", arguments: { sessionId } },
      });
    }
    if (id === "read-conversation") {
      notify("item/completed", {
        threadId: dynamicTurn.threadId,
        turnId: dynamicTurn.turnId,
        item: { type: "dynamicToolCall", id: "read-item", tool: "read_conversation", status: "completed", success: result?.success },
      });
      const sessionId = dynamicTurn.sessionId;
      notify("item/started", {
        threadId: dynamicTurn.threadId,
        turnId: dynamicTurn.turnId,
        item: { type: "dynamicToolCall", id: "open-item", tool: "open_conversation", arguments: { sessionId }, status: "inProgress" },
      });
      return send({
        id: "open-conversation",
        method: "item/tool/call",
        params: { threadId: dynamicTurn.threadId, turnId: dynamicTurn.turnId, callId: "open-item", namespace: null, tool: "open_conversation", arguments: { sessionId } },
      });
    }
    if (id === "open-conversation") {
      notify("item/completed", {
        threadId: dynamicTurn.threadId,
        turnId: dynamicTurn.turnId,
        item: { type: "dynamicToolCall", id: "open-item", tool: "open_conversation", status: "completed", success: result?.success },
      });
      completeTurn(dynamicTurn.threadId, dynamicTurn.turnId);
      dynamicTurn = null;
      return;
    }
  }
  if (method === "initialized") return;
  if (method === "initialize") return reply(id);
  if (method === "account/read") {
    return reply(id, { account });
  }
  if (method === "account/login/start") {
    if (params.type === "apiKey") {
      account = { type: "apiKey" };
      return reply(id, { type: "apiKey" });
    }
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
    setTimeout(() => {
      if (!error) account = { type: "chatgpt", planType: "plus" };
      notify("account/login/completed", { loginId, success: !error, error });
    }, 10);
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
  if (method === "thread/inject_items") {
    return scenario === "context-compaction-inject-failure" ? fail(id, "could not seed thread") : reply(id);
  }
  if (method === "thread/delete") return reply(id);
  if (method === "thread/unsubscribe") return reply(id, { status: "unsubscribed" });
  if (method === "turn/start") {
    if (scenario === "expired") return fail(id, "unauthorized: ChatGPT login expired");
    if (scenario === "exhausted") return fail(id, "Codex allowance usage limit reached");
    if (scenario === "reconnect" && marker && !existsSync(marker)) {
      writeFileSync(marker, "restarted\n");
      process.exit(23);
    }
    const turnId = `turn-${++turnCounter}`;
    const handoff = params.input?.some?.((item) => typeof item.text === "string" && item.text.includes("continuation handoff")) ?? false;
    reply(id, { turn: { id: turnId } });
    if (scenario === "session-navigation") {
      dynamicTurn = { threadId: params.threadId, turnId };
      notify("item/started", {
        threadId: params.threadId,
        turnId,
        item: { type: "dynamicToolCall", id: "list-item", tool: "list_conversations", arguments: {}, status: "inProgress" },
      });
      return send({
        id: "list-conversations",
        method: "item/tool/call",
        params: { threadId: params.threadId, turnId, callId: "list-item", namespace: null, tool: "list_conversations", arguments: {} },
      });
    }
    if (scenario !== "cancel") setTimeout(() => completeTurn(params.threadId, turnId, handoff), 5);
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
