#!/usr/bin/env node
import { loadConfig } from "../core/config.js";
import { readSecret, writeSecret } from "../core/credentials.js";
import { OpenAIModelClient } from "../core/model.js";
import { A1RRuntime } from "../core/runtime.js";
import { Store } from "../core/store.js";
import { RuntimeServer } from "./server.js";

const config = loadConfig();
const store = new Store(config.homeDir);
const model = new OpenAIModelClient(config, readSecret("openai", config.homeDir));
const runtime = new A1RRuntime(config, store, model);
const server = new RuntimeServer(config, runtime, store, {
  openAIConfigured: () => model.isConfigured(),
  setOpenAIKey: async (key) => {
    await model.setApiKey(key);
    writeSecret("openai", key, config.homeDir);
  },
});

const port = await server.listen();
if (process.send) process.send({ type: "ready", port });
else console.log(`A1R runtime listening on http://${config.host}:${port}`);

let closing = false;
async function close(): Promise<void> {
  if (closing) return;
  closing = true;
  await server.close();
  store.close();
  process.exit(0);
}

process.on("SIGINT", close);
process.on("SIGTERM", close);
