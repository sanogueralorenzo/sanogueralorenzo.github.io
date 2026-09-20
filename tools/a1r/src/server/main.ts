#!/usr/bin/env node
import { loadConfig } from "../core/config.js";
import { readSecret, writeSecret } from "../core/credentials.js";
import { BackendRegistry } from "../core/backend.js";
import { OpenAIModelClient } from "../core/model.js";
import { ResponsesBackend } from "../core/responses-backend.js";
import { A1RRuntime } from "../core/runtime.js";
import { Store } from "../core/store.js";
import { createA1RCodexAppServer } from "../codex/app-server.js";
import { CodexBackend } from "../codex/backend.js";
import { BackendSetupService } from "../setup/service.js";
import { RuntimeServer } from "./server.js";

const config = loadConfig();
const store = new Store(config.homeDir);
const model = new OpenAIModelClient(config, readSecret("openai", config.homeDir));
const responses = new ResponsesBackend(config, store, model);
const codexClient = createA1RCodexAppServer(config);
const codex = new CodexBackend(config, store, codexClient);
const backends = new BackendRegistry(store, responses, codex);
const runtime = new A1RRuntime(config, store, backends);
const setup = new BackendSetupService(store, model, codexClient, (key) => {
  writeSecret("openai", key, config.homeDir);
});
const server = new RuntimeServer(config, runtime, store, {
  status: () => setup.status(),
  setOpenAIKey: (key) => setup.setOpenAIKey(key),
  selectBackend: (backend) => setup.selectBackend(backend),
  startCodexLogin: (mode) => setup.startCodexLogin(mode),
  codexLoginStatus: (loginId) => setup.codexLoginStatus(loginId),
  cancelCodexLogin: (loginId) => setup.cancelCodexLogin(loginId),
});

const port = await server.listen();
if (process.send) process.send({ type: "ready", port });
else console.log(`A1R runtime listening on http://${config.host}:${port}`);

let closing = false;
async function close(): Promise<void> {
  if (closing) return;
  closing = true;
  await server.close();
  await codex.close();
  store.close();
  process.exit(0);
}

process.on("SIGINT", close);
process.on("SIGTERM", close);
