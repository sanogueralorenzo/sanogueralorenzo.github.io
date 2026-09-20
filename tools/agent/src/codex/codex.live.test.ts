import { on } from "node:events";
import { homedir } from "node:os";
import { join } from "node:path";
import { expect, it } from "vitest";
import { cleanup, temporary } from "../test-support.js";
import { createAgentCodexAppServer } from "./app-server.js";
import type { JsonRpcMessage } from "./protocol.js";

const live = process.env.AGENT_LIVE_CODEX === "1" ? it : it.skip;

live("runs an opt-in Codex subscription turn without reading stored credentials", async () => {
  const cwd = temporary("agent-codex-live-");
  const client = createAgentCodexAppServer(
    { homeDir: process.env.AGENT_HOME ?? join(homedir(), ".agent"), codexCommand: process.env.AGENT_CODEX_COMMAND ?? "codex" },
    { requestTimeoutMs: 60_000 },
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
