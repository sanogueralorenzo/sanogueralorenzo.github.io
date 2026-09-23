#!/usr/bin/env node
import { loadConfig } from "../local/config.js";
import { execFileSync, spawn } from "node:child_process";
import { networkInterfaces } from "node:os";
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

function tailscaleIPv4(): string {
  let address: string;
  try {
    address = execFileSync("tailscale", ["ip", "-4"], { encoding: "utf8", stdio: ["ignore", "pipe", "ignore"], timeout: 3000 }).trim();
  } catch {
    throw new Error("Could not query Tailscale. Make sure its CLI is installed, logged in, and connected.");
  }
  const octets = address.split(".").map(Number);
  const isTailscaleRange = octets.length === 4 && octets.every((octet) => Number.isInteger(octet) && octet >= 0 && octet <= 255)
    && octets[0] === 100 && octets[1]! >= 64 && octets[1]! <= 127;
  const isAssignedLocally = Object.values(networkInterfaces()).flatMap((interfaces) => interfaces ?? [])
    .some((entry) => entry.family === "IPv4" && entry.address === address);
  if (!isTailscaleRange || !isAssignedLocally) {
    throw new Error("Tailscale did not report an active IPv4 address for this Mac.");
  }
  return address;
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

async function startAgentRuntime(tailnetAddress?: string): Promise<void> {
  const store = new Store(config.homeDir);
  const codexClient = createAgentCodexAppServer(config);
  const codex = new CodexBackend(config, store, codexClient);
  const runtime = new AgentRuntime(store, codex, new CodexHomeBackend(config, store, codexClient));
  const setup = new AgentSetupService(codexClient);
  const server = new RuntimeServer(config, runtime, store, setup);

  const port = await server.listen();
  let proxy: WebsiteProxy | undefined;
  let url = `http://127.0.0.1:${port}`;
  if (webRequested && tailnetAddress) {
    try {
      const runtime = readPrivateJson<ExistingRuntime>(join(config.homeDir, "runtime.json"));
      if (!runtime) throw new Error("Could not read the local Agent runtime connection details.");
      proxy = new WebsiteProxy(runtime, config.homeDir);
      const proxyPort = await proxy.listen(0, tailnetAddress);
      url = `http://${tailnetAddress}:${proxyPort}`;
    } catch (error) {
      proxy?.close();
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
  const tailnetAddress = tailscaleRequested ? tailscaleIPv4() : undefined;
  const existing = await inspectExistingRuntime();
  if (existing?.website) {
    if (!tailnetAddress || !existing.runtime) openWebsite(existing.url);
    else {
      const proxyPort = existing.runtime.port + 1;
      const proxyUrl = `http://${tailnetAddress}:${proxyPort}`;
      if (proxyPort <= 65535 && await servesWebsite(proxyUrl)) {
        openWebsite(proxyUrl);
        process.exit(0);
      }
      const proxy = new WebsiteProxy(existing.runtime, config.homeDir);
      const port = await proxy.listen(proxyPort <= 65535 ? proxyPort : 0, tailnetAddress);
      openWebsite(`http://${tailnetAddress}:${port}`);
      process.on("SIGINT", () => proxy.close());
      process.on("SIGTERM", () => proxy.close());
    }
  } else if (existing) {
    if (!existing.runtime) {
      console.error(`Another service is using ${existing.url}; Agent will not replace its runtime file.`);
      process.exit(1);
    }
    const proxyPort = existing.runtime.port + 1;
    const proxyHost = tailnetAddress ?? "127.0.0.1";
    const proxyUrl = `http://${proxyHost}:${proxyPort}`;
    if (proxyPort <= 65535 && await servesWebsite(proxyUrl)) {
      openWebsite(proxyUrl);
      process.exit(0);
    }
    const proxy = new WebsiteProxy(existing.runtime, config.homeDir);
    const port = await proxy.listen(!tailnetAddress && proxyPort <= 65535 ? proxyPort : 0, proxyHost);
    openWebsite(`http://${proxyHost}:${port}`);
    process.on("SIGINT", () => proxy.close());
    process.on("SIGTERM", () => proxy.close());
  } else {
    await startAgentRuntime(tailnetAddress);
  }
} else {
  await startAgentRuntime();
}
