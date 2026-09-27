import { spawn, type ChildProcessWithoutNullStreams } from "node:child_process";
import { existsSync, readFileSync, readdirSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import { createInterface, type Interface } from "node:readline";
import { defineTool } from "@earendil-works/pi-coding-agent";
import { Type } from "typebox";

type RpcMessage = { id?: number; method?: string; params?: Record<string, unknown>; result?: Record<string, unknown>; error?: { message?: string } };
type Pending = { resolve: (value: Record<string, unknown>) => void; reject: (error: Error) => void };
type McpConfig = { command: string; args: string[]; env: Record<string, string> };
type ToolContent = { type: "text"; text: string } | { type: "image"; data: string; mimeType: string };

function mcpConfig(): McpConfig {
  const root = join(process.env.CODEX_HOME || join(homedir(), ".codex"), "plugins", "cache", "openai-bundled", "unified-computer-use");
  const versions = existsSync(root) ? readdirSync(root).sort((a, b) => b.localeCompare(a, undefined, { numeric: true })) : [];
  for (const version of versions) {
    const file = join(root, version, ".mcp.json");
    if (!existsSync(file)) continue;
    const config = JSON.parse(readFileSync(file, "utf8")) as { mcpServers?: { cua_repl?: McpConfig } };
    const server = config.mcpServers?.cua_repl;
    if (server && existsSync(server.command) && server.args.every(existsSync)) return server;
  }
  throw new Error("Codex Computer Use is unavailable. Install and enable its plugin in the Codex app.");
}

export class ComputerUseClient {
  private process?: ChildProcessWithoutNullStreams;
  private lines?: Interface;
  private ready?: Promise<void>;
  private nextId = 0;
  private pending = new Map<number, Pending>();
  private stderr = "";
  private closed = false;

  private send(message: Record<string, unknown>) {
    if (!this.process?.stdin.writable) throw new Error("Computer Use server is not running");
    this.process.stdin.write(`${JSON.stringify({ jsonrpc: "2.0", ...message })}\n`);
  }

  private request(method: string, params: Record<string, unknown>, signal?: AbortSignal): Promise<Record<string, unknown>> {
    if (signal?.aborted) return Promise.reject(new Error("Computer Use stopped"));
    const id = ++this.nextId;
    return new Promise((resolve, reject) => {
      const abort = () => { this.close(); reject(new Error("Computer Use stopped")); };
      this.pending.set(id, { resolve: (value) => { signal?.removeEventListener("abort", abort); resolve(value); },
        reject: (error) => { signal?.removeEventListener("abort", abort); reject(error); } });
      signal?.addEventListener("abort", abort, { once: true });
      try { this.send({ id, method, params }); }
      catch (error) { this.pending.delete(id); signal?.removeEventListener("abort", abort); reject(error); }
    });
  }

  private handleServerRequest(message: RpcMessage) {
    if (message.method !== "elicitation/create" || message.id === undefined) return;
    try { this.send({ id: message.id, result: { action: "accept", content: {} } }); }
    catch { /* The server may already have exited. */ }
  }

  private async start() {
    if (this.closed) throw new Error("Computer Use session is closed");
    if (this.ready) return this.ready;
    this.ready = (async () => {
      const config = mcpConfig();
      const child = spawn(config.command, config.args, { env: { ...process.env, ...config.env }, stdio: ["pipe", "pipe", "pipe"] });
      this.process = child;
      this.lines = createInterface({ input: child.stdout });
      this.lines.on("line", (line) => {
        let response: RpcMessage;
        try { response = JSON.parse(line) as RpcMessage; } catch { return; }
        if (response.method) { this.handleServerRequest(response); return; }
        if (response.id === undefined) return;
        const pending = this.pending.get(response.id);
        if (!pending) return;
        this.pending.delete(response.id);
        if (response.error) pending.reject(new Error(response.error.message || "Computer Use request failed"));
        else pending.resolve(response.result || {});
      });
      child.stderr.on("data", (chunk: Buffer) => { this.stderr = `${this.stderr}${chunk.toString()}`.slice(-2000); });
      const failed = (error: Error) => {
        for (const pending of this.pending.values()) pending.reject(error);
        this.pending.clear();
      };
      child.on("error", failed);
      child.on("exit", (code) => failed(new Error(`Computer Use server exited (${code}): ${this.stderr}`)));
      await this.request("initialize", { protocolVersion: "2024-11-05", capabilities: { elicitation: { form: {} } }, clientInfo: { name: "assistant-pi", version: "0.1.0" } });
      this.send({ method: "notifications/initialized" });
    })();
    return this.ready;
  }

  async call(code: string, title: string | undefined, timeoutMs: number | undefined, signal?: AbortSignal) {
    await this.start();
    const result = await this.request("tools/call", { name: "js", arguments: { code, ...(title && { title }), ...(timeoutMs && { timeout_ms: timeoutMs }) } }, signal);
    const blocks = Array.isArray(result.content) ? result.content : [];
    const content: ToolContent[] = [];
    for (const block of blocks) {
      if (typeof block !== "object" || block === null) continue;
      const item = block as Record<string, unknown>;
      if (item.type === "text" && typeof item.text === "string") content.push({ type: "text", text: item.text });
      if (item.type === "image" && typeof item.data === "string" && typeof item.mimeType === "string")
        content.push({ type: "image", data: item.data, mimeType: item.mimeType });
    }
    if (result.isError) throw new Error(content.filter((item) => item.type === "text").map((item) => item.text).join("\n") || "Computer Use failed");
    return { content: content.length ? content : [{ type: "text" as const, text: "Done." }], details: undefined };
  }

  tool() {
    return defineTool({
      name: "computer_use", label: "Use your computer",
      description: "Control native apps and browsers through Codex Computer Use. JavaScript state persists across calls in this turn. On the first call, execute exactly one entry point: await cua.getState() to list available surfaces, await cua.getApp(\"App Name\") for a named app, await cua.getTab(...) for a known tab, or await cua.createBrowserTab(...) for a new tab. Read the returned API documentation before further calls. Use only documented cua APIs and verify changes from fresh UI state. Return text with nodeRepl.write(value) or images with await nodeRepl.emitImage(image).",
      parameters: Type.Object({ code: Type.String({ minLength: 1 }), title: Type.Optional(Type.String()), timeout_ms: Type.Optional(Type.Integer({ minimum: 1 })) }),
      execute: async (_id, params, signal) => this.call(params.code, params.title, params.timeout_ms, signal),
    });
  }

  close() {
    if (this.closed) return;
    this.closed = true;
    this.lines?.close();
    this.process?.kill();
    for (const pending of this.pending.values()) pending.reject(new Error("Computer Use session closed"));
    this.pending.clear();
  }
}
