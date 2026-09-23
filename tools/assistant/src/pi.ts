import { readFileSync } from "node:fs";
import { join } from "node:path";
import { createAgentSession, DefaultResourceLoader, getAgentDir, ModelRuntime, SessionManager, type AgentSession, type AgentSessionEvent, type ExtensionAPI, type ToolDefinition } from "@earendil-works/pi-coding-agent";
import type { TaskRole } from "./state.ts";
import { assistantCodexAuth } from "./codex-auth.ts";

const prompts = new URL("../prompts/", import.meta.url);
const prompt = (name: string) => readFileSync(new URL(`${name}.md`, prompts), "utf8");
export const assistantText = (message: { role?: string; content?: unknown }): string => {
  if (message.role !== "assistant" || !Array.isArray(message.content)) return "";
  return message.content.filter((part): part is { type: "text"; text: string } =>
    typeof part === "object" && part !== null && "type" in part && part.type === "text" && "text" in part && typeof part.text === "string")
    .map((part) => part.text).join("\n").trim();
};
function displayUser(text: string) {
  // Older sessions included a routing scope after the original message.
  if (!text.startsWith("Original user message (verbatim):\n")) return text;
  return text.slice("Original user message (verbatim):\n".length).split("\n\nAssigned scope:")[0];
}

export class PiService {
  private readonly dataDir: string;
  private readonly runtime: Promise<ModelRuntime>;
  constructor(dataDir: string) {
    this.dataDir = dataDir;
    this.runtime = ModelRuntime.create({ authPath: assistantCodexAuth(dataDir) });
  }
  private async make(cwd: string, role: "coordinator" | "reporter" | TaskRole, manager: SessionManager, customTools: ToolDefinition[] = []): Promise<AgentSession> {
    const modelRuntime = await this.runtime;
    const model = modelRuntime.getModel("openai-codex", "gpt-6-luna");
    if (!model) throw new Error("Codex model gpt-6-luna is unavailable in the pinned Pi catalog");
    const fast = (pi: ExtensionAPI) => pi.on("before_provider_request", ({ payload }) => {
      if (typeof payload !== "object" || payload === null || Array.isArray(payload)) throw new Error("Unexpected Codex request payload");
      // The Codex subscription endpoint accepts the legacy Fast alias.
      return { ...payload, service_tier: "priority" };
    });
    const worker = role !== "coordinator" && role !== "reporter";
    const loader = new DefaultResourceLoader({
      cwd, agentDir: getAgentDir(), noExtensions: true, extensionFactories: [fast], noPromptTemplates: true,
      noSkills: !worker, noContextFiles: !worker,
      systemPromptOverride: () => [prompt("base"), prompt(role)].join("\n\n"),
      appendSystemPromptOverride: () => [],
    });
    await loader.reload();
    const tools = role === "coordinator" ? customTools.map((tool) => tool.name)
      : role === "reporter" ? []
      : role === "scout" || role === "reviewer" ? ["read", "grep", "find", "ls"]
      : ["read", "bash", "edit", "write", "grep", "find", "ls"];
    const { session } = await createAgentSession({ cwd, modelRuntime, model, thinkingLevel: role === "coordinator" ? "low" : "high",
      resourceLoader: loader, sessionManager: manager, customTools, tools });
    return session;
  }
  async create(cwd: string, id: string, role: TaskRole) {
    return this.make(cwd, role, SessionManager.create(cwd, join(this.dataDir, "sessions"), { id }));
  }
  async open(cwd: string, file: string, role: TaskRole) {
    return this.make(cwd, role, SessionManager.open(file, join(this.dataDir, "sessions"), cwd));
  }
  async utility(role: "coordinator" | "reporter", input: string, cwd: string, customTools: ToolDefinition[] = [], acceptedResult?: () => string | undefined) {
    const session = await this.make(cwd, role, SessionManager.create(cwd, join(this.dataDir, role)), customTools);
    const unsubscribe = acceptedResult ? session.subscribe((event) => {
      // Pi would make another model call after the accepted tool result; the routing plan is already complete.
      if (event.type === "tool_execution_end" && acceptedResult()) void session.abort();
    }) : undefined;
    try {
      try { await session.prompt(input, { expandPromptTemplates: false }); }
      catch (error) { if (!acceptedResult?.()) throw error; }
      const accepted = acceptedResult?.();
      if (accepted) return accepted;
      const last = [...session.messages].reverse().find((message) => message.role === "assistant");
      if (last?.stopReason === "error") throw new Error(last.errorMessage || `${role} model request failed`);
      const text = last ? assistantText(last) : "";
      if (!text) throw new Error(`${role} returned no answer`);
      return text;
    } finally { unsubscribe?.(); session.dispose(); }
  }
  transcript(file: string) {
    const manager = SessionManager.open(file);
    return manager.getEntries().filter((entry) => entry.type === "message")
      .map((entry) => entry.message).filter((message) => message.role === "user" || message.role === "assistant")
      .map((message) => ({ role: message.role, text: message.role === "assistant" ? assistantText(message) : displayUser(
        Array.isArray(message.content) ? message.content.filter((part) => part.type === "text").map((part) => part.text).join("\n") : String(message.content)) }))
      .filter((message) => message.text.trim());
  }
}
export type PiEvent = AgentSessionEvent;
