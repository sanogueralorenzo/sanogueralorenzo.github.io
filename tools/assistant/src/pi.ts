import { existsSync, readFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import { createAgentSession, DefaultResourceLoader, getAgentDir, ModelRuntime, SessionManager, type AgentSession, type AgentSessionEvent, type ExtensionAPI, type ToolDefinition } from "@earendil-works/pi-coding-agent";
import type { TaskRole } from "./state.ts";
import { assistantCodexAuth } from "./codex-auth.ts";
import { enableHostedSearch } from "./hosted-search.ts";

const prompts = new URL("../prompts/", import.meta.url);
const prompt = (name: string) => readFileSync(new URL(`${name}.md`, prompts), "utf8");
export const assistantText = (message: { role?: string; content?: unknown }): string => {
  if (message.role !== "assistant" || !Array.isArray(message.content)) return "";
  return message.content.filter((part): part is { type: "text"; text: string } =>
    typeof part === "object" && part !== null && "type" in part && part.type === "text" && "text" in part && typeof part.text === "string")
    // Failed hosted page opens can leave Pi's empty citation marker in the text.
    .map((part) => part.text).join("\n").replace(/\s*\(\[\]\(\)\)/g, "").trim();
};
export class PiService {
  private readonly dataDir: string;
  private readonly runtime: Promise<ModelRuntime>;
  constructor(dataDir: string) {
    this.dataDir = dataDir;
    this.runtime = ModelRuntime.create({ authPath: assistantCodexAuth(dataDir) }).then((runtime) => {
      enableHostedSearch(runtime);
      return runtime;
    });
  }
  private async make(cwd: string, role: "coordinator" | TaskRole, manager: SessionManager, customTools: ToolDefinition[] = []): Promise<AgentSession> {
    const modelRuntime = await this.runtime;
    const model = modelRuntime.getModel("openai-codex", "gpt-6-luna");
    if (!model) throw new Error("Codex model gpt-6-luna is unavailable in the pinned Pi catalog");
    const fast = (pi: ExtensionAPI) => pi.on("before_provider_request", ({ payload }) => {
      if (typeof payload !== "object" || payload === null || Array.isArray(payload)) throw new Error("Unexpected Codex request payload");
      const request = payload as Record<string, unknown>;
      // The Codex subscription endpoint accepts the legacy Fast alias.
      return { ...request, service_tier: "priority", ...(role === "coordinator" ? {} : { tools: [...(Array.isArray(request.tools) ? request.tools : []), { type: "web_search" }] }) };
    });
    const worker = role !== "coordinator";
    const cuaSkill = join(homedir(), ".cua-driver", "skills", "cua-driver");
    const loader = new DefaultResourceLoader({
      cwd, agentDir: getAgentDir(), noExtensions: true, extensionFactories: [fast], noPromptTemplates: true,
      noSkills: !worker, noContextFiles: !worker,
      additionalSkillPaths: (role === "personal" || role === "code") && existsSync(cuaSkill) ? [cuaSkill] : [],
      systemPromptOverride: () => [prompt("base"), `Current local date: ${new Date().toLocaleDateString("en-US", { dateStyle: "full" })}.`, prompt(role)].join("\n\n"),
      appendSystemPromptOverride: () => [],
    });
    await loader.reload();
    const availableTools = customTools;
    const tools = role === "coordinator" ? availableTools.map((tool) => tool.name)
      : role === "scout" || role === "reviewer" ? ["read", "grep", "find", "ls"]
      : ["read", "bash", "edit", "write", "grep", "find", "ls"];
    const { session } = await createAgentSession({ cwd, modelRuntime, model, thinkingLevel: role === "coordinator" ? "low" : "high",
      resourceLoader: loader, sessionManager: manager, customTools: availableTools, tools });
    return session;
  }
  async create(cwd: string, id: string, role: TaskRole) {
    return this.make(cwd, role, SessionManager.create(cwd, join(this.dataDir, "sessions"), { id }));
  }
  async open(cwd: string, file: string, role: TaskRole) {
    return this.make(cwd, role, SessionManager.open(file, join(this.dataDir, "sessions"), cwd));
  }
  async utility(role: "coordinator", input: string, cwd: string, customTools: ToolDefinition[] = [], acceptedResult?: () => string | undefined) {
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
      .map((message) => ({ role: message.role, text: message.role === "assistant" ? assistantText(message) :
        Array.isArray(message.content) ? message.content.filter((part) => part.type === "text").map((part) => part.text).join("\n") : String(message.content) }))
      .filter((message) => message.text.trim());
  }
}
export type PiEvent = AgentSessionEvent;
