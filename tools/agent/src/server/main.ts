#!/usr/bin/env node
import { loadConfig } from "../local/config.js";
import { readSecret, writeSecret } from "../local/credentials.js";
import { BackendRegistry } from "../conversation/backend.js";
import { OpenAIModelClient } from "../openai/model.js";
import { ResponsesBackend } from "../openai/responses-backend.js";
import { AgentRuntime } from "../conversation/runtime.js";
import { Store } from "../conversation/store.js";
import { createAgentCodexAppServer } from "../codex/app-server.js";
import { CodexBackend } from "../codex/backend.js";
import { BackendSetupService } from "../setup/service.js";
import { RuntimeServer } from "./server.js";

const config = loadConfig();
const store = new Store(config.homeDir);
const model = new OpenAIModelClient(readSecret("openai", config.homeDir));
const responses = new ResponsesBackend(config, store, model);
const codexClient = createAgentCodexAppServer(config);
const codex = new CodexBackend(config, store, codexClient);
const backends = new BackendRegistry(store, responses, codex);
const runtime = new AgentRuntime(store, backends);
const setup = new BackendSetupService(store, model, codexClient, (key) => {
  writeSecret("openai", key, config.homeDir);
});
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
