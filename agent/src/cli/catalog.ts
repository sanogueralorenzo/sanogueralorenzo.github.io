import { tmpdir } from "node:os";
import type { ModelRef } from "@earendil-works/pi-durable";
import { cliStatus, startCli } from "./process.ts";

export const cliProviders = [
  { id: "openai", name: "Codex", command: "codex", login: "codex login", defaultModel: "gpt-6.1-sol",
    utilityModel: "gpt-6-luna", window: 400_000, models: [["gpt-6.1-sol", "GPT-6.1 Sol"], ["gpt-6-astra", "GPT-6 Astra"], ["gpt-6-luna", "GPT-6 Luna"]] },
  { id: "anthropic", name: "Claude Code", command: "claude", login: "claude auth login", defaultModel: "claude-sonnet-5-5",
    utilityModel: "claude-haiku-5-5", window: 200_000, models: [["claude-fable-5-1", "Claude Fable 5.1"], ["claude-opus-5-5", "Claude Opus 5.5"],
      ["claude-sonnet-5-5", "Claude Sonnet 5.5"], ["claude-haiku-5-5", "Claude Haiku 5.5"]] },
  { id: "google", name: "Google Antigravity", command: "agy", login: "agy acp --login", defaultModel: "gemini-4-argon",
    utilityModel: "gemini-3.5-flash-lite", window: 200_000, models: [["gemini-4-argon", "Gemini 4 Argon"],
      ["gemini-3.8-flash", "Gemini 3.8 Flash"], ["gemini-3.5-flash-lite", "Gemini 3.5 Flash-Lite"]] },
] as const;
export type CliProvider = typeof cliProviders[number];
export const defaultModel: ModelRef = { provider: "openai", modelId: "gpt-6-luna" };

export function cliProvider(id: string) { return cliProviders.find(provider => provider.id === id); }

async function googleConnected(cwd: string, signal: AbortSignal) {
  const cli = startCli("agy", ["acp"], cwd, signal);
  const events = cli.events();
  try {
    cli.send({ jsonrpc: "2.0", id: 1, method: "initialize", params: {
      protocolVersion: 1, clientCapabilities: {}, clientInfo: { name: "agent", version: "0.1.0" },
    } });
    for await (const event of events) {
      if (event.id === 1 && event.result) {
        cli.send({ jsonrpc: "2.0", id: 2, method: "session/list", params: { cwd } });
      }
      if (event.id === 2) return Array.isArray(event.result?.sessions);
    }
    return false;
  } finally { await cli.stop(); }
}

export async function cliConnection(provider: CliProvider, closing: AbortSignal) {
  const cwd = tmpdir();
  const signal = AbortSignal.any([closing, AbortSignal.timeout(6000)]);
  const installed = await cliStatus(provider.command, ["--version"], cwd, signal) !== undefined;
  if (!installed) return { installed, connected: false };
  let connected = false;
  try {
    if (provider.id === "openai") {
      const status = await cliStatus(provider.command, ["login", "status"], cwd, signal);
      connected = status !== undefined;
    } else if (provider.id === "anthropic") {
      const status = await cliStatus(provider.command, ["auth", "status", "--json"], cwd, signal);
      connected = !!status && JSON.parse(status).loggedIn === true;
    } else connected = await googleConnected(cwd, signal);
  } catch {}
  return { installed, connected };
}

export function fastSupported(provider: string, modelId: string) {
  return provider === "openai" || (provider === "anthropic" && modelId === "claude-opus-5-5");
}
