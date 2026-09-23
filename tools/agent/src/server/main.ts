#!/usr/bin/env node
import { loadConfig } from "../local/config.js";
import { execFileSync, spawn } from "node:child_process";
import { join } from "node:path";
import { AgentRuntime } from "../conversation/runtime.js";
import { Store } from "../conversation/store.js";
import { createAgentCodexAppServer } from "../codex/app-server.js";
import { CodexBackend } from "../codex/backend.js";
import { CodexHomeBackend } from "../home/codex.js";
import { AgentSetupService } from "../setup/service.js";
import { readPrivateJson } from "../local/files.js";
import { RuntimeServer } from "./server.js";
import { WebsiteProxy, type ExistingRuntime } from "./web-proxy.js";

const config = loadConfig();
const webRequested = process.env.AGENT_OPEN_WEB === "1";
const tailscaleRequested = process.env.AGENT_TAILSCALE_WEB === "1";

function tailscaleServeUrl(port: number): string {
  let current: string;
  try {
    current = execFileSync("tailscale", ["serve", "status"], { encoding: "utf8", stdio: ["ignore", "pipe", "ignore"], timeout: 5000 }).trim();
  } catch {
    throw new Error("Could not inspect Tailscale Serve. Make sure Tailscale is installed, logged in, and connected.");
  }
  const target = `http://127.0.0.1:${port}`;
  const urlIn = (value: string) => value.match(/https:\/\/[A-Za-z0-9.-]+(?::[0-9]+)?/)?.[0];
  if (current !== "No serve config") {
    if (current.includes(`proxy ${target}`)) {
      const url = urlIn(current);
      if (url) return url;
    }
    throw new Error("Tailscale Serve already has a different configuration. Agent left it unchanged; check `tailscale serve status`.");
  }
  let output: string;
  try {
    output = execFileSync("tailscale", ["serve", "--bg", String(port)], { encoding: "utf8", stdio: ["ignore", "pipe", "ignore"], timeout: 10000 }).trim();
  } catch {
    throw new Error("Could not enable Tailscale Serve. Check that MagicDNS and HTTPS certificates are enabled for this tailnet.");
  }
  const url = urlIn(output);
  if (url) return url;
  try {
    const status = execFileSync("tailscale", ["serve", "status"], { encoding: "utf8", stdio: ["ignore", "pipe", "ignore"], timeout: 5000 });
    const configuredUrl = urlIn(status);
    if (status.includes(`proxy ${target}`) && configuredUrl) return configuredUrl;
  } catch { /* Preserve the more useful setup message below. */ }
  throw new Error("Tailscale Serve started, but its tailnet URL could not be determined. Check `tailscale serve status`.");
}

async function inspectExistingRuntime(): Promise<{ url: string; website: boolean; runtime: ExistingRuntime | null } | null> {
  const existing = readPrivateJson<ExistingRuntime>(join(config.homeDir, "runtime.json"));
  if (!existing || !existing.token || !Number.isInteger(existing.port) || existing.port < 1 || existing.port > 65535) return null;
  const url = `http://127.0.0.1:${existing.port}`;
  try {
    const health = await fetch(`${url}/v1/health`, { signal: AbortSignal.timeout(1500) });
    if (!health.ok) return null;
    const healthStatus = await health.json() as { pid?: number };
    if (healthStatus.pid !== existing.pid) return { url, website: false, runtime: null };
    const isWebsite = await servesWebsite(url);
    return { url, website: isWebsite, runtime: existing };
  } catch {
    return null;
  }
}

async function servesWebsite(url: string): Promise<boolean> {
  try {
    const page = await fetch(`${url}/`, { signal: AbortSignal.timeout(1500) });
    return page.ok && Boolean(page.headers.get("content-type")?.startsWith("text/html"))
      && (await page.text()).includes("/web/app.css");
  } catch { return false; }
}

function openWebsite(url: string): void {
  console.log(`Agent website: ${url}`);
  if (process.platform === "darwin") {
    const browser = spawn("open", [url], { detached: true, stdio: "ignore" });
    browser.unref();
  }
}

async function startAgentRuntime(useTailscaleServe = false): Promise<void> {
  const store = new Store(config.homeDir);
  const codexClient = createAgentCodexAppServer(config);
  const codex = new CodexBackend(config, store, codexClient);
  const runtime = new AgentRuntime(store, codex, new CodexHomeBackend(config, store, codexClient));
  const setup = new AgentSetupService(codexClient);
  const server = new RuntimeServer(config, runtime, store, setup);

  const port = await server.listen();
  let proxy: WebsiteProxy | undefined;
  let url = `http://127.0.0.1:${port}`;
  if (webRequested && useTailscaleServe) {
    try {
      url = tailscaleServeUrl(port);
    } catch (error) {
      await server.close();
      codexClient.stop();
      store.close();
      throw error;
    }
  }
  if (process.send) process.send({ type: "ready", port });
  else if (webRequested) openWebsite(url);
  else console.log(`Agent runtime listening on ${url}`);

  let closing = false;
  async function close(): Promise<void> {
    if (closing) return;
    closing = true;
    proxy?.close();
    await server.close();
    codexClient.stop();
    store.close();
    process.exit(0);
  }

  process.on("SIGINT", close);
  process.on("SIGTERM", close);
}

if (webRequested) {
  const existing = await inspectExistingRuntime();
  if (existing?.website) {
    if (!tailscaleRequested || !existing.runtime) openWebsite(existing.url);
    else {
      const proxy = new WebsiteProxy(existing.runtime, config.homeDir);
      try {
        const port = await proxy.listen();
        openWebsite(tailscaleServeUrl(port));
      } catch (error) {
        proxy.close();
        throw error;
      }
      process.on("SIGINT", () => proxy.close());
      process.on("SIGTERM", () => proxy.close());
    }
  } else if (existing) {
    if (!existing.runtime) {
      console.error(`Another service is using ${existing.url}; Agent will not replace its runtime file.`);
      process.exit(1);
    }
    const proxyPort = existing.runtime.port + 1;
    const proxyUrl = `http://127.0.0.1:${proxyPort}`;
    if (proxyPort <= 65535 && await servesWebsite(proxyUrl)) {
      openWebsite(tailscaleRequested ? tailscaleServeUrl(proxyPort) : proxyUrl);
      process.exit(0);
    }
    const proxy = new WebsiteProxy(existing.runtime, config.homeDir);
    try {
      const port = await proxy.listen(proxyPort <= 65535 ? proxyPort : 0);
      openWebsite(tailscaleRequested ? tailscaleServeUrl(port) : `http://127.0.0.1:${port}`);
    } catch (error) {
      proxy.close();
      throw error;
    }
    process.on("SIGINT", () => proxy.close());
    process.on("SIGTERM", () => proxy.close());
  } else {
    await startAgentRuntime(tailscaleRequested);
  }
} else {
  await startAgentRuntime();
}
