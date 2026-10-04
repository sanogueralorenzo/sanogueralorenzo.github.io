import { readFileSync } from "node:fs";
import { DefaultResourceLoader, getAgentDir, type ExtensionAPI, type ExtensionFactory } from "@earendil-works/pi-coding-agent";
import { trackHostedSearch } from "./hosted-search.ts";

export type AgentRole = "coordinator" | "session" | "researcher" | "reviewer";
const prompts = new URL("../prompts/", import.meta.url);
export const readPrompt = (name: string) => readFileSync(new URL(`${name}.md`, prompts), "utf8");

export function providerTools(role: AgentRole, report: (label: string) => void): ExtensionFactory {
  return (pi: ExtensionAPI) => {
    trackHostedSearch(pi, report);
    pi.on("before_provider_request", ({ payload }) => {
      if (typeof payload !== "object" || payload === null || Array.isArray(payload)) throw new Error("Unexpected Codex request payload");
      const request = payload as Record<string, unknown>;
      return { ...request, service_tier: "priority", ...(role === "coordinator" ? {} : { tools: [...(Array.isArray(request.tools) ? request.tools : []), { type: "web_search" }] }) };
    });
  };
}

export function agentResources(cwd: string, role: AgentRole, extensions: ExtensionFactory[], instructions = [readPrompt("base"), readPrompt(role)]) {
  return new DefaultResourceLoader({
    cwd, agentDir: getAgentDir(), noExtensions: true, extensionFactories: extensions, noPromptTemplates: true,
    noSkills: role === "coordinator", noContextFiles: role === "coordinator",
    systemPromptOverride: () => [instructions[0], `Current local date: ${new Date().toLocaleDateString("en-US", { dateStyle: "full" })}.`, ...instructions.slice(1)].join("\n\n"),
    appendSystemPromptOverride: () => [],
  });
}

export function agentToolNames(role: AgentRole, customNames: string[]) {
  return role === "coordinator" ? customNames : role === "session"
    ? ["read", "bash", "edit", "write", "grep", "find", "ls", "delegate", "computer_use"]
    : ["read", "grep", "find", "ls"];
}
