import { readFileSync } from "node:fs";
import { DefaultResourceLoader, getAgentDir } from "@earendil-works/pi-coding-agent";

export type AgentRole = "router" | "dispatcher" | "coordinator" | "worker";
const prompts = new URL("../prompts/", import.meta.url);
export const readPrompt = (name: string) => readFileSync(new URL(`${name}.md`, prompts), "utf8");

export function agentResources(cwd: string, role: AgentRole, instructions?: string[]) {
  const utility = role === "router" || role === "dispatcher";
  const sections = instructions ?? [readPrompt("base"), ...(!utility ? [readPrompt("work")] : []), readPrompt(role)];
  return new DefaultResourceLoader({
    cwd, agentDir: getAgentDir(), noExtensions: true, noPromptTemplates: true,
    noSkills: utility, noContextFiles: utility,
    systemPromptOverride: () => [sections[0], `Current local date: ${new Date().toLocaleDateString("en-US", { dateStyle: "full" })}.`, ...sections.slice(1)].join("\n\n"),
    appendSystemPromptOverride: () => [],
  });
}
