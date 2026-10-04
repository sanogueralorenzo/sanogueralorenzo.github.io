import { readFileSync, writeFileSync, mkdirSync, mkdtempSync, readdirSync } from "node:fs";
import { join, resolve, relative, dirname, isAbsolute } from "node:path";
import { tmpdir } from "node:os";
import { createAgentSession, SessionManager } from "@earendil-works/pi-coding-agent";
import { agentResources, agentToolNames, providerTools } from "../../src/agent-resources.ts";
import { assistantText } from "../../src/pi.ts";
import { hash } from "./suite.mjs";

export function workspacePath(root, path = ".") {
  // Native Pi tools strip @ and expand ~ before resolving a path.
  path = path.replace(/^@/, "").replace(/[\u00a0\u2000-\u200a\u202f\u205f\u3000]/g, " ");
  if (path.startsWith("~")) throw new Error("Path is outside the benchmark workspace");
  const full = resolve(root, path);
  const rel = relative(root, full);
  if (rel === ".." || rel.startsWith("../") || isAbsolute(rel)) throw new Error("Path is outside the benchmark workspace");
  return full;
}

export function workspaceSnapshot(root) {
  const files = {};
  const visit = dir => {
    for (const item of readdirSync(dir, { withFileTypes: true }).sort((a, b) => a.name.localeCompare(b.name))) {
      const path = join(dir, item.name);
      if (item.isSymbolicLink()) throw new Error("Benchmark workspaces must not contain symlinks");
      if (item.isDirectory()) visit(path);
      else files[relative(root, path)] = hash(readFileSync(path));
    }
  };
  visit(root);
  return files;
}

export function recordAssistantMessage(record, message, normalize = text => text) {
  for (const key of Object.keys(record.usage)) record.usage[key] += message.usage?.[key] || 0;
  const text = message.content.filter(p => p.type === "text").map(p => p.text).join("\n");
  record.trace.push({ role: "assistant", text: normalize(text), calls: message.content.filter(p => p.type === "toolCall"), stopReason: message.stopReason });
  record.text = normalize(assistantText(message));
  record.completed = message.stopReason === "stop";
  if (message.stopReason === "error") {
    record.error = message.errorMessage || "Provider failed";
    record.providerErrors = [...(record.providerErrors || []), record.error];
  } else delete record.error;
}

export async function runResearcherIntegration(runtime, model, suite, job, options = {}) {
  const { test, variant, repeat, id } = job;
  const parent = options.workspaceDir || join(tmpdir(), "assistant-researcher-benchmark");
  mkdirSync(parent, { recursive: true });
  const cwd = mkdtempSync(join(parent, `${test.id}-`));
  for (const [path, content] of Object.entries(test.files || {})) {
    const target = workspacePath(cwd, path);
    mkdirSync(dirname(target), { recursive: true });
    const projectRules = path === "AGENTS.md" ? readFileSync(new URL("../../../../AGENTS.md", import.meta.url), "utf8") + "\nAdditional project instructions:\n" : "";
    writeFileSync(target, projectRules + content, { mode: 0o600 });
  }
  const before = workspaceSnapshot(cwd);
  const started = performance.now();
  const record = { id, caseId: test.id, family: test.family, category: test.category, variant: variant.id, repeat,
    trace: [], state: {}, usage: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, totalTokens: 0 }, requests: [], text: "" };
  let session; let timer; let turns = 0; let limited = false;
  const callArguments = new Map();
  const observer = pi => {
    pi.on("tool_call", event => {
      try { workspacePath(cwd, event.input.path || "."); }
      catch { return { block: true, reason: "Benchmark read boundary: path is outside the isolated workspace." }; }
    });
    pi.on("before_provider_request", ({ payload }) => {
      const requested = { model: payload.model, effort: payload.reasoning?.effort, tier: payload.service_tier,
        tools: payload.tools?.map(t => t.name || t.type), instructionCharacters: payload.instructions?.length,
        preamblePresent: payload.instructions?.includes(variant.sections[0]) };
      if (requested.effort !== variant.effort || !requested.tools.includes("web_search")) throw new Error("Integration provider configuration differs from production");
      record.requests.push({ request: requested });
    });
    pi.on("provider_stream_event", ({ data }) => {
      if (!data || typeof data !== "object") return;
      if (data.type === "response.completed") record.requests.at(-1).response = { model: data.response?.model,
        tier: data.response?.service_tier, reasoningTokens: data.response?.usage?.output_tokens_details?.reasoning_tokens };
      if (data.type === "response.output_item.done" && data.item?.type === "web_search_call")
        record.trace.push({ role: "tool", name: "web_search", arguments: data.item.action || {}, text: JSON.stringify(data.item) });
    });
  };
  try {
    const loader = agentResources(cwd, "researcher", [providerTools("researcher", () => {}), observer], variant.sections);
    await loader.reload();
    ({ session } = await createAgentSession({ cwd, modelRuntime: runtime, model, thinkingLevel: variant.effort,
      resourceLoader: loader, sessionManager: SessionManager.inMemory(cwd), tools: agentToolNames("researcher", []) }));
    const normalize = text => text.replaceAll(cwd, "<workspace>");
    record.environment = { systemPrompt: normalize(session.systemPrompt), systemPromptHash: hash(normalize(session.systemPrompt)),
      tools: session.getActiveToolNames(), skills: loader.getSkills().skills.map(s => ({ name: s.name, description: s.description, path: normalize(s.filePath) })),
      context: loader.getAgentsFiles().agentsFiles.map(f => ({ path: normalize(f.path), hash: hash(f.content) })), files: before };
    for (const file of loader.getAgentsFiles().agentsFiles) record.trace.push({ role: "context", name: "project_instructions", text: normalize(file.content), path: normalize(file.path) });
    session.subscribe(event => {
      if (event.type === "tool_execution_start") callArguments.set(event.toolCallId, event.args);
      if (event.type === "message_end" && event.message.role === "assistant") {
        const message = event.message;
        recordAssistantMessage(record, message, normalize);
        if (++turns >= (suite.config.maxTurns || 8) && !record.completed) { limited = true; void session.abort(); }
      }
      if (event.type === "tool_execution_end") record.trace.push({ role: "tool", name: event.toolName,
        arguments: JSON.parse(normalize(JSON.stringify(callArguments.get(event.toolCallId) || {}))), text: normalize((event.result?.content || []).filter(p => p.type === "text").map(p => p.text).join("\n")), error: event.isError });
    });
    timer = setTimeout(() => { limited = true; void session.abort(); }, suite.config.timeoutMs || 180000);
    for (const message of test.messages) {
      if (message.role !== "user") throw new Error("Real delegated researchers take user task messages, not fabricated assistant history");
      await session.prompt(message.text, { expandPromptTemplates: false });
      if (limited || record.error) break;
    }
    if (limited || !record.completed) record.agentFailure = "Integration turn/time budget exhausted without a final answer";
    record.state = { unchanged: hash(before) === hash(workspaceSnapshot(cwd)) };
  } catch (error) {
    if (limited) record.agentFailure = "Integration turn/time budget exhausted without a final answer";
    else record.error = error.message;
  }
  finally { clearTimeout(timer); session?.dispose(); }
  record.elapsedMs = performance.now() - started;
  record.deadlineExceeded = record.elapsedMs > (suite.config.deadlineMs || 180000);
  return record;
}
