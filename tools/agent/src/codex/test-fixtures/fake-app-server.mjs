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
function completeTurn(threadId, turnId) {
  if (scenario === "context-compaction") {
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
    delta: "Hello from Codex.",
  });
  notify("turn/completed", { threadId, turn: { id: turnId, status: "completed" } });
}

readline.createInterface({ input: process.stdin }).on("line", (line) => {
  const { id, method, params = {}, result } = JSON.parse(line);
  if (log) appendFileSync(log, `${JSON.stringify(method
    ? { method, params: params.apiKey ? { ...params, apiKey: "[redacted]" } : params }
    : { id, result })}\n`);
  if (!method && id === "open-folder" && dynamicTurn) {
    notify("item/completed", {
      threadId: dynamicTurn.threadId,
      turnId: dynamicTurn.turnId,
      item: { type: "dynamicToolCall", id: "folder-item", tool: "open_folder", status: "completed", success: result?.success },
    });
    notify("item/agentMessage/delta", { threadId: dynamicTurn.threadId, turnId: dynamicTurn.turnId, delta: "Stale turn text." });
    notify("turn/completed", { threadId: dynamicTurn.threadId, turn: { id: dynamicTurn.turnId, status: "completed" } });
    dynamicTurn = null;
    return;
  }
  if (!method && id === "read-history" && dynamicTurn) {
    notify("item/completed", {
      threadId: dynamicTurn.threadId,
      turnId: dynamicTurn.turnId,
      item: { type: "dynamicToolCall", id: "history-item", tool: "read_history", status: "completed", success: result?.success },
    });
    notify("item/agentMessage/delta", { threadId: dynamicTurn.threadId, turnId: dynamicTurn.turnId, delta: "Here are the saved messages." });
    notify("turn/completed", { threadId: dynamicTurn.threadId, turn: { id: dynamicTurn.turnId, status: "completed" } });
    dynamicTurn = null;
    return;
  }
  if (!method && id === "home-tool" && dynamicTurn) {
    notify("turn/completed", { threadId: dynamicTurn.threadId, turn: { id: dynamicTurn.turnId, status: "completed" } });
    dynamicTurn = null;
    return;
  }
  if (!method && id === "home-find" && dynamicTurn) {
    const found = JSON.parse(result?.contentItems?.[0]?.text ?? "[]");
    if (scenario === "home-read") {
      dynamicTurn.sessionId = found[0]?.id;
      return send({ id: "home-read", method: "item/tool/call", params: {
        threadId: dynamicTurn.threadId, turnId: dynamicTurn.turnId, callId: "home-read",
        tool: "read_conversation", arguments: { sessionId: dynamicTurn.sessionId },
      } });
    }
    return send({ id: "home-tool", method: "item/tool/call", params: {
      threadId: dynamicTurn.threadId, turnId: dynamicTurn.turnId, callId: "home-tool",
      tool: "continue_task", arguments: { sessionId: found[0]?.id, title: "Open Tonal Android" },
    } });
  }
  if (!method && id === "home-read" && dynamicTurn) {
    const read = JSON.parse(result?.contentItems?.[0]?.text ?? "{}");
    return send({ id: "home-tool", method: "item/tool/call", params: {
      threadId: dynamicTurn.threadId, turnId: dynamicTurn.turnId, callId: "home-tool",
      tool: "continue_task", arguments: {
        sessionId: read.conversation?.id,
        title: "Continue reconnect investigation",
        text: "Continue the reconnect investigation with the additional logs.",
      },
    } });
  }
  if (!method && scenario.startsWith("session-navigation") && dynamicTurn) {
    if (id === "list-conversations") {
      const conversations = JSON.parse(result?.contentItems?.[0]?.text ?? "[]");
      const sessionId = (conversations.find((conversation) => conversation.title === "Telegram reconnects") ?? conversations[0])?.id;
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
      const argumentsValue = { sessionId, ...(scenario === "session-navigation-task" ? { task: "Fix the reconnect flow" } : {}) };
      notify("item/started", {
        threadId: dynamicTurn.threadId,
        turnId: dynamicTurn.turnId,
        item: { type: "dynamicToolCall", id: "open-item", tool: "open_conversation", arguments: argumentsValue, status: "inProgress" },
      });
      return send({
        id: "open-conversation",
        method: "item/tool/call",
        params: { threadId: dynamicTurn.threadId, turnId: dynamicTurn.turnId, callId: "open-item", namespace: null, tool: "open_conversation", arguments: argumentsValue },
      });
    }
    if (id === "open-conversation") {
      notify("item/completed", {
        threadId: dynamicTurn.threadId,
        turnId: dynamicTurn.turnId,
        item: { type: "dynamicToolCall", id: "open-item", tool: "open_conversation", status: "completed", success: result?.success },
      });
      if (scenario === "session-navigation-completed") {
        notify("item/completed", {
          threadId: dynamicTurn.threadId,
          turnId: dynamicTurn.turnId,
          item: { type: "agentMessage", text: "Opened the conversation." },
        });
        notify("turn/completed", { threadId: dynamicTurn.threadId, turn: { id: dynamicTurn.turnId, status: "completed" } });
      } else {
        completeTurn(dynamicTurn.threadId, dynamicTurn.turnId);
      }
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
    reply(id, { turn: { id: turnId } });
    if (scenario === "home-find" || scenario === "home-read") {
      dynamicTurn = { threadId: params.threadId, turnId };
      return send({ id: "home-find", method: "item/tool/call", params: {
        threadId: params.threadId, turnId, callId: "home-find", tool: "find_conversations",
        arguments: { query: scenario === "home-read" ? "Reconnect" : "Tonal" },
      } });
    }
    if (scenario === "home-compose" || scenario === "home-report") {
      dynamicTurn = { threadId: params.threadId, turnId };
      const tool = scenario === "home-compose" ? "start_task" : "report_task";
      const args = scenario === "home-compose"
        ? { text: "Fix the tests", title: "Fix tests" }
        : { state: "ready", summary: "The tests now pass and the app runs cleanly on your Mac today" };
      return send({ id: "home-tool", method: "item/tool/call", params: {
        threadId: params.threadId, turnId, callId: "home-tool", tool, arguments: args,
      } });
    }
    if (scenario.startsWith("workspace-open") && turnCounter === 1) {
      dynamicTurn = { threadId: params.threadId, turnId };
      const argumentsValue = { path: process.env.AGENT_FAKE_WORKSPACE, ...(scenario === "workspace-open-task" ? { task: "Fix the tests" } : {}) };
      notify("item/started", {
        threadId: params.threadId,
        turnId,
        item: { type: "dynamicToolCall", id: "folder-item", tool: "open_folder", arguments: argumentsValue, status: "inProgress" },
      });
      return send({
        id: "open-folder",
        method: "item/tool/call",
        params: { threadId: params.threadId, turnId, callId: "folder-item", namespace: null, tool: "open_folder", arguments: argumentsValue },
      });
    }
    if (scenario.startsWith("session-navigation") && turnCounter === 1) {
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
    if (scenario === "history") {
      dynamicTurn = { threadId: params.threadId, turnId };
      notify("item/started", {
        threadId: params.threadId,
        turnId,
        item: { type: "dynamicToolCall", id: "history-item", tool: "read_history", arguments: {}, status: "inProgress" },
      });
      return send({
        id: "read-history",
        method: "item/tool/call",
        params: { threadId: params.threadId, turnId, callId: "history-item", namespace: null, tool: "read_history", arguments: {} },
      });
    }
    if (scenario !== "cancel") setTimeout(() => completeTurn(params.threadId, turnId), 5);
    return;
  }
  if (method === "turn/interrupt") {
    reply(id);
    return notify("turn/completed", { threadId: params.threadId, turn: { id: params.turnId, status: "interrupted" } });
  }
  if (method === "turn/steer") return reply(id, { turnId: params.expectedTurnId });
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
