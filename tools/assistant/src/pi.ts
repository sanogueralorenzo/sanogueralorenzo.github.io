import { readFileSync } from "node:fs";
import { join } from "node:path";
import { createAgentSession, DefaultResourceLoader, defineTool, getAgentDir, ModelRuntime, SessionManager, type AgentSession, type AgentSessionEvent, type ExtensionAPI, type ToolDefinition } from "@earendil-works/pi-coding-agent";
import { Type } from "typebox";
import { assistantCodexAuth } from "./codex-auth.ts";
import { ComputerUseClient } from "./computer-use.ts";
import { trackHostedSearch } from "./hosted-search.ts";

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
  private readonly computers = new WeakMap<AgentSession, ComputerUseClient>();
  private readonly searchActivity = new WeakMap<AgentSession, (label: string) => void>();
  constructor(dataDir: string) {
    this.dataDir = dataDir;
    this.runtime = ModelRuntime.create({ authPath: assistantCodexAuth(dataDir) });
  }
  private delegateTool(cwd: string) {
    return defineTool({
      name: "delegate", label: "Delegate read-only work",
      description: "Ask a separate read-only researcher to investigate or reviewer to critique. Give it a focused task and any context it needs. You own the final answer and all actions.",
      parameters: Type.Object({ role: Type.Union([Type.Literal("researcher"), Type.Literal("reviewer")]), task: Type.String({ minLength: 1 }) }),
      execute: async (_id, params, signal) => {
        if (signal?.aborted) throw new Error("Delegation stopped");
        const child = await this.make(cwd, params.role, SessionManager.inMemory(cwd));
        const abort = () => { void child.abort(); };
        signal?.addEventListener("abort", abort, { once: true });
        try {
          if (signal?.aborted) throw new Error("Delegation stopped");
          await child.prompt(params.task, { expandPromptTemplates: false });
          const last = [...child.messages].reverse().find((message) => message.role === "assistant");
          if (last?.stopReason === "error") throw new Error(last.errorMessage || "Worker failed");
          const result = last ? assistantText(last) : "";
          if (!result) throw new Error("Worker returned no answer");
          return { content: [{ type: "text" as const, text: result }], details: undefined };
        } finally { signal?.removeEventListener("abort", abort); this.dispose(child); }
      },
    });
  }
  private async make(cwd: string, role: "coordinator" | "session" | "researcher" | "reviewer", manager: SessionManager, customTools: ToolDefinition[] = []): Promise<AgentSession> {
    const modelRuntime = await this.runtime;
    const model = modelRuntime.getModel("openai-codex", "gpt-6-luna");
    if (!model) throw new Error("Codex model gpt-6-luna is unavailable in the pinned Pi catalog");
    const providerTools = (pi: ExtensionAPI) => {
      trackHostedSearch(pi, (label) => this.searchActivity.get(session)?.(label));
      pi.on("before_provider_request", ({ payload }) => {
        if (typeof payload !== "object" || payload === null || Array.isArray(payload)) throw new Error("Unexpected Codex request payload");
        const request = payload as Record<string, unknown>;
        return { ...request, service_tier: "priority", ...(role === "coordinator" ? {} : { tools: [...(Array.isArray(request.tools) ? request.tools : []), { type: "web_search" }] }) };
      });
    };
    const sessionAgent = role === "session";
    const loader = new DefaultResourceLoader({
      cwd, agentDir: getAgentDir(), noExtensions: true, extensionFactories: [providerTools], noPromptTemplates: true,
      noSkills: role === "coordinator", noContextFiles: role === "coordinator",
      systemPromptOverride: () => [prompt("base"), `Current local date: ${new Date().toLocaleDateString("en-US", { dateStyle: "full" })}.`, prompt(role)].join("\n\n"),
      appendSystemPromptOverride: () => [],
    });
    await loader.reload();
    const computer = sessionAgent ? new ComputerUseClient() : undefined;
    const availableTools = sessionAgent ? [...customTools, this.delegateTool(cwd), computer!.tool()] : customTools;
    const tools = role === "coordinator" ? availableTools.map((tool) => tool.name)
      : sessionAgent ? ["read", "bash", "edit", "write", "grep", "find", "ls", "delegate", "computer_use"]
      : ["read", "grep", "find", "ls"];
    const { session } = await createAgentSession({ cwd, modelRuntime, model, thinkingLevel: role === "coordinator" ? "low" : "high",
      resourceLoader: loader, sessionManager: manager, customTools: availableTools, tools });
    if (computer) this.computers.set(session, computer);
    return session;
  }
  dispose(session: AgentSession) {
    this.searchActivity.delete(session);
    this.computers.get(session)?.close();
    this.computers.delete(session);
    session.dispose();
  }
  onSearchActivity(session: AgentSession, report: (label: string) => void) {
    this.searchActivity.set(session, report);
  }
  async create(cwd: string, id: string) {
    return this.make(cwd, "session", SessionManager.create(cwd, join(this.dataDir, "sessions"), { id }));
  }
  async open(cwd: string, file: string) {
    return this.make(cwd, "session", SessionManager.open(file, join(this.dataDir, "sessions"), cwd));
  }
  async utility(role: "coordinator", input: string, cwd: string, customTools: ToolDefinition[] = [], acceptedResult?: () => string | undefined) {
    const session = await this.make(cwd, role, SessionManager.inMemory(cwd), customTools);
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
    } finally { unsubscribe?.(); this.dispose(session); }
  }
  transcript(file: string) {
    const manager = SessionManager.open(file);
    let reaction: "thumbs-up" | undefined;
    return manager.getEntries().flatMap((entry) => {
      if (entry.type === "custom" && entry.customType === "assistant-reaction") {
        reaction = "thumbs-up";
        return [];
      }
      if (entry.type !== "message") return [];
      const { id, message } = entry;
      if (message.role !== "user" && message.role !== "assistant") return [];
      const userReaction = message.role === "user" ? reaction : undefined;
      if (message.role === "user") reaction = undefined;
      return [{ id, role: message.role, ...(userReaction && { reaction: userReaction }), replyable: message.role === "assistant" && message.stopReason !== "toolUse", text: message.role === "assistant" ? assistantText(message) :
        Array.isArray(message.content) ? message.content.filter((part) => part.type === "text").map((part) => part.text).join("\n") : String(message.content) }];
    })
      .filter((message) => message.text.trim());
  }
}
export type PiEvent = AgentSessionEvent;
