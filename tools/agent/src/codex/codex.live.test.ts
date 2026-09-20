import { mkdtempSync, rmSync } from "node:fs";
import { homedir, tmpdir } from "node:os";
import { join } from "node:path";
import { expect, it } from "vitest";
import { createAgentCodexAppServer } from "./app-server.js";

const live = process.env.AGENT_LIVE_CODEX === "1" ? it : it.skip;

live("runs an opt-in Codex subscription turn without reading stored credentials", async () => {
  const cwd = mkdtempSync(join(tmpdir(), "agent-codex-live-"));
  const client = createAgentCodexAppServer(
    { homeDir: process.env.AGENT_HOME ?? join(homedir(), ".agent"), codexCommand: process.env.AGENT_CODEX_COMMAND ?? "codex" },
    { requestTimeoutMs: 60_000 },
  );
  try {
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
    let output = "";
    const completed = new Promise<void>((resolve, reject) => {
      const timer = setTimeout(() => reject(new Error("Live Codex turn timed out.")), 90_000);
      const unsubscribe = client.onNotification((message) => {
        if (message.params?.threadId !== started.thread.id) return;
        if (message.method === "item/agentMessage/delta" && typeof message.params.delta === "string") output += message.params.delta;
        if (message.method === "turn/completed") {
          clearTimeout(timer);
          unsubscribe();
          const turn = message.params.turn as { status?: string; error?: { message?: string } } | undefined;
          if (turn?.status === "completed") resolve();
          else reject(new Error(turn?.error?.message ?? `Live Codex turn ended as ${turn?.status ?? "unknown"}.`));
        }
      });
    });
    await client.request("turn/start", {
      threadId: started.thread.id,
      input: [{ type: "text", text: "Reply with: Agent live smoke passed", text_elements: [] }],
    });
    await completed;
    expect(output).toContain("Agent");
  } finally {
    await client.stop();
    rmSync(cwd, { recursive: true, force: true });
  }
}, 120_000);
