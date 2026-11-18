import { readFileSync } from "node:fs";
import { DefaultResourceLoader, getAgentDir } from "@earendil-works/pi-coding-agent";

export type AgentRole = "router" | "dispatcher" | "coordinator" | "worker";
const prompts = new URL("../prompts/", import.meta.url);
export const readPrompt = (name: string) => readFileSync(new URL(`${name}.md`, prompts), "utf8");

export function agentResources(cwd: string, role: AgentRole, instructions = [readPrompt("base"), readPrompt(role)]) {
  return new DefaultResourceLoader({
    cwd, agentDir: getAgentDir(), noExtensions: true, noPromptTemplates: true,
    noSkills: ["router", "dispatcher"].includes(role), noContextFiles: ["router", "dispatcher"].includes(role),
    systemPromptOverride: () => [instructions[0], `Current local date: ${new Date().toLocaleDateString("en-US", { dateStyle: "full" })}.`, ...instructions.slice(1)].join("\n\n"),
    appendSystemPromptOverride: () => [],
  });
}
