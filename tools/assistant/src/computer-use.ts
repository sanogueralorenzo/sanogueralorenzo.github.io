import { existsSync, readFileSync, readdirSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import { McpClient, McpTimeoutError, StdioTransport, toLlmContent } from "@earendil-works/pi-mcp";
import { defineTool } from "@earendil-works/pi-durable";
import { Type } from "typebox";

type McpConfig = { command: string; args: string[]; env: Record<string, string> };

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
  private readonly client = new McpClient({ name: "assistant-pi", version: "0.1.0", capabilities: { elicitation: { form: {} } } });
  private readonly config: () => McpConfig;
  private ready?: Promise<void>;
  private closing?: Promise<void>;
  constructor(config = mcpConfig) {
    this.config = config;
    this.client.setRequestHandler("elicitation/create", () => ({ action: "accept", content: {} }));
  }
  private async start() {
    if (this.closing || this.client.connectionState === "closed") throw new Error("Computer Use session is closed");
    return this.ready ||= this.client.connect(new StdioTransport(this.config())).then(() => {});
  }
  async call(code: string, title: string | undefined, timeoutMs: number | undefined, signal?: AbortSignal) {
    signal?.throwIfAborted();
    const abort = () => { queueMicrotask(() => { void this.close().catch(() => {}); }); };
    signal?.addEventListener("abort", abort, { once: true });
    try {
      await this.start();
      signal?.throwIfAborted();
      const result = await this.client.callTool("js", { code, ...(title && { title }), ...(timeoutMs !== undefined && { timeout_ms: timeoutMs }) }, {
        signal,
        // Let the server enforce its JS limit, with a transport grace period. Unspecified limits stay server-owned.
        timeoutMs: timeoutMs === undefined ? 0 : timeoutMs + 5000,
      });
      const content = toLlmContent(result);
      if (result.isError) throw new Error(content.filter((item) => item.type === "text").map((item) => item.text).join("\n") || "Computer Use failed");
      return { content: content.length ? content : [{ type: "text" as const, text: "Done." }] };
    } catch (error) {
      if (signal?.aborted || error instanceof McpTimeoutError) await this.close();
      if (signal?.aborted) throw new Error("Computer Use stopped");
      throw error;
    } finally { signal?.removeEventListener("abort", abort); }
  }
  tool() {
    return defineTool({
      name: "computer_use", replay: "unsafe", executionMode: "sequential",
      description: "Control native apps and browsers through Codex Computer Use. JavaScript state persists across calls in this turn. On the first call, execute exactly one entry point: await cua.getState() to list available surfaces, await cua.getApp(\"App Name\") for a named app, await cua.getTab(...) for a known tab, or await cua.createBrowserTab(...) for a new tab. Read the returned API documentation before further calls. Use only documented cua APIs and verify changes from fresh UI state. Return text with nodeRepl.write(value) or images with await nodeRepl.emitImage(image).",
      parameters: Type.Object({ code: Type.String({ minLength: 1 }), title: Type.Optional(Type.String()), timeout_ms: Type.Optional(Type.Integer({ minimum: 1 })) }),
      execute: async (params, _api, context) => this.call(params.code, params.title, params.timeout_ms, context.abortSignal),
    });
  }
  close() { return this.closing ||= this.client.close(); }
}
