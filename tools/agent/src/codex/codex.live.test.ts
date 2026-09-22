import { on } from "node:events";
import { realpathSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import { expect, it } from "vitest";
import { cleanup, temporary } from "../test-support.js";
import { createAgentCodexAppServer } from "./app-server.js";
import { CodexBackend } from "./backend.js";
import { Store } from "../conversation/store.js";
import type { JsonRpcMessage } from "./protocol.js";

it("runs an opt-in Codex subscription turn without reading stored credentials", async () => {
  const cwd = temporary("agent-codex-live-");
  const client = createAgentCodexAppServer(
    { homeDir: process.env.AGENT_HOME ?? join(homedir(), ".agent"), codexCommand: process.env.AGENT_CODEX_COMMAND ?? "codex" },
  );
  cleanup(() => client.stop());
  const account = await client.account(true);
  expect(account.account?.type, "Run `agent setup --chatgpt` first.").toBe("chatgpt");
  const started = await client.request<{ thread: { id: string } }>("thread/start", {
    cwd,
    ephemeral: true,
    approvalPolicy: "never",
    sandbox: "read-only",
    developerInstructions: "This is an Agent protocol smoke test. Do not use tools. Reply briefly.",
    threadSource: "appServer",
  });
  const notifications = on(client, "notification", { signal: AbortSignal.timeout(90_000) });
  await client.request("turn/start", {
    threadId: started.thread.id,
    input: [{ type: "text", text: "Reply with: Agent live smoke passed", text_elements: [] }],
  });
  let output = "";
  for await (const [value] of notifications) {
    const message = value as JsonRpcMessage;
    if (message.params?.threadId !== started.thread.id) continue;
    if (message.method === "item/agentMessage/delta" && typeof message.params.delta === "string") output += message.params.delta;
    if (message.method === "turn/completed") {
      expect((message.params.turn as { status?: string }).status).toBe("completed");
      break;
    }
  }
  expect(output).toContain("Agent");
}, 120_000);

it("routes a project-and-task request through an ephemeral Codex turn", async () => {
  const project = temporary("agent-route-live-project-");
  const agentHome = process.env.AGENT_HOME ?? join(homedir(), ".agent");
  const store = new Store(temporary("agent-route-live-store-"));
  cleanup(() => store.close());
  const client = createAgentCodexAppServer({ homeDir: agentHome, codexCommand: process.env.AGENT_CODEX_COMMAND ?? "codex" });
  cleanup(() => client.stop());
  const backend = new CodexBackend({ homeDir: agentHome, port: 0, codexCommand: "codex" }, store, client);
  const session = store.createSession();
  const handoff = await backend.route({
    session,
    request: { text: `Open the project at ${project} and explain what cwd means.` },
    instructions: "",
    sessionTools: [],
  });
  expect(handoff).toMatchObject({ destination: { cwd: realpathSync(project) } });
  expect(handoff?.task).toBeTruthy();
  const navigationOnly = await backend.route({
    session,
    request: { text: `Open the project at ${project}.` },
    instructions: "",
    sessionTools: [],
  });
  expect(navigationOnly).toEqual({ destination: { cwd: realpathSync(project) }, task: null });
}, 120_000);

it("finds a saved conversation and carries the follow-on task", async () => {
  const agentHome = process.env.AGENT_HOME ?? join(homedir(), ".agent");
  const store = new Store(temporary("agent-conversation-live-store-"));
  cleanup(() => store.close());
  const client = createAgentCodexAppServer({ homeDir: agentHome, codexCommand: process.env.AGENT_CODEX_COMMAND ?? "codex" });
  cleanup(() => client.stop());
  const backend = new CodexBackend({ homeDir: agentHome, port: 0, codexCommand: "codex" }, store, client);
  const saved = store.createSession({ title: "Purple otter experiment" });
  store.addMessage(saved.id, "user", "The purple otter experiment tracks river water levels.");
  const current = store.createSession({ title: "Current discussion" });
  const handoff = await backend.route({
    session: current,
    request: { text: "Resume the purple otter conversation and summarize what it tracks." },
    instructions: "",
    sessionTools: store.sessionCards().filter((card) => card.id !== current.id),
  });
  expect(handoff).toMatchObject({ destination: { sessionId: saved.id } });
  expect(handoff?.task).toBeTruthy();
}, 120_000);
