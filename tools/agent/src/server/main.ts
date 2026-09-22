#!/usr/bin/env node
import { loadConfig } from "../local/config.js";
import { AgentRuntime } from "../conversation/runtime.js";
import { Store } from "../conversation/store.js";
import { createAgentCodexAppServer } from "../codex/app-server.js";
import { CodexBackend } from "../codex/backend.js";
import { CodexHomeBackend } from "../home/codex.js";
import { AgentSetupService } from "../setup/service.js";
import { RuntimeServer } from "./server.js";

const config = loadConfig();
const store = new Store(config.homeDir);
const codexClient = createAgentCodexAppServer(config);
const codex = new CodexBackend(config, store, codexClient);
const runtime = new AgentRuntime(store, codex, new CodexHomeBackend(config, store, codexClient));
const setup = new AgentSetupService(codexClient);
const server = new RuntimeServer(config, runtime, store, setup);

const port = await server.listen();
if (process.send) process.send({ type: "ready", port });
else console.log(`Agent runtime listening on http://127.0.0.1:${port}`);

let closing = false;
async function close(): Promise<void> {
  if (closing) return;
  closing = true;
  await server.close();
  codexClient.stop();
  store.close();
  process.exit(0);
}

process.on("SIGINT", close);
process.on("SIGTERM", close);
