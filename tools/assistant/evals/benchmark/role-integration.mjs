import { readFileSync, writeFileSync, mkdirSync, mkdtempSync, readdirSync, lstatSync } from "node:fs";
import { join, dirname, relative, resolve, sep } from "node:path";
import { tmpdir } from "node:os";
import { Type } from "typebox";
import { BACKGROUND_CONTEXT } from "@earendil-works/chord/context";
import { createRegistry, defineExtension, defineTool, Harness, hook, MemoryStorage, ToolTask } from "@earendil-works/pi-durable";
import { roleExtension, providerModels } from "../../src/pi.ts";
import { agentResources } from "../../src/agent-resources.ts";
import { HomeRouter } from "../../src/home-routing.ts";
import { ComputerUseClient } from "../../src/computer-use.ts";
import { workspacePath, workspaceSnapshot, recordAssistantMessage } from "./integration-workspace.mjs";
import { hash } from "./suite.mjs";
import { matches } from "./trial.mjs";

function rejectSymlinks(path) {
  let stat;
  try { stat = lstatSync(path); }
  catch (error) { if (error.code === "ENOENT") return; throw error; }
  if (stat.isSymbolicLink()) throw new Error("Benchmark paths must not contain symlinks");
  if (stat.isDirectory()) for (const child of readdirSync(path)) rejectSymlinks(join(path, child));
}

export function roleToolBoundary(cwd, test, event) {
  try {
    if (event.toolName === "bash") {
      if (typeof event.input.command !== "string" || !(test.allowedCommands || []).includes(event.input.command))
        throw new Error("Bash command is not in the exact authored allowedCommands whitelist");
      rejectSymlinks(cwd);
      return;
    }
    if (!["read", "edit", "write", "grep", "find", "ls"].includes(event.toolName)) return;
    const input = event.input.path ?? ".";
    if (typeof input !== "string") throw new Error("File path must be a string");
    rejectSymlinks(cwd);
    // Native read also tries these filename spellings on macOS.
    for (const spelling of new Set([input, input.normalize("NFD"), input.replaceAll("'", "’"), input.normalize("NFD").replaceAll("'", "’"), input.replace(/ (AM|PM)\./gi, "\u202f$1.")])) {
      const path = workspacePath(cwd, spelling);
      let current = cwd;
      for (const segment of relative(cwd, path).split(sep).filter(Boolean)) {
        current = join(current, segment);
        let stat;
        try { stat = lstatSync(current); }
        catch (error) { if (error.code === "ENOENT") break; throw error; }
        if (stat.isSymbolicLink()) throw new Error("Benchmark paths must not contain symlinks");
      }
      rejectSymlinks(path);
    }
  } catch (error) { return { block: true, reason: `Benchmark workspace boundary: ${error.message}. No action was executed.` }; }
}

function sessionFixtureTools(test, variant) {
  const definitions = [{ name: "delegate", label: "Delegate read-only work",
    description: "Ask a separate read-only researcher to investigate or reviewer to critique. Give it a focused task and any context it needs. You own the final answer and all actions.",
    parameters: Type.Object({ role: Type.Union([Type.Literal("researcher"), Type.Literal("reviewer")]), task: Type.String({ minLength: 1 }) }) },
  new ComputerUseClient().tool()];
  return definitions.map(definition => defineTool({ ...definition,
    execute: async (args) => {
      const fixture = (test.fixtures || []).find(item => item.tool === definition.name && matches(args, item.match || {}));
      if (!fixture) throw new Error(`${definition.name} is disabled in native role integration; no external action was executed. Supply an explicit fixture reply to exercise this boundary.`);
      const text = fixture.resource ? variant.resources?.[fixture.resource] : fixture.response;
      if (fixture.error) throw new Error(text || `${definition.name} fixture failed`);
      if (typeof text !== "string") throw new Error(`${definition.name} fixture needs a text response`);
      return { content: [{ type: "text", text }], details: { fixture: true } };
    } }));
}

export async function runRoleIntegration(runtime, model, suite, job, options = {}) {
  const { test: authoredTest, variant, repeat, id } = job;
  const role = suite.config.role;
  if (!["researcher", "reviewer", "session", "coordinator"].includes(role)) throw new Error("Role integration requires reviewer, session, or coordinator");
  if (role === "coordinator" && authoredTest.messages?.length !== 1)
    throw new Error("Coordinator integration supports one new Home message per case; seed prior routed exchanges in homeState");
  const parent = resolve(options.workspaceDir || join(tmpdir(), "assistant-role-benchmark"));
  workspacePath(resolve(tmpdir()), parent);
  mkdirSync(parent, { recursive: true });
  const cwd = mkdtempSync(join(parent, "case-"));
  const test = JSON.parse(JSON.stringify(authoredTest).replaceAll("<workspace>", cwd));
  for (const [path, content] of Object.entries(test.files || {})) {
    const target = workspacePath(cwd, path);
    mkdirSync(dirname(target), { recursive: true });
    const projectRules = path === "AGENTS.md" ? readFileSync(new URL("../../../../AGENTS.md", import.meta.url), "utf8") + "\nAdditional project instructions:\n" : "";
    writeFileSync(target, projectRules + content, { mode: 0o600 });
  }
  const before = workspaceSnapshot(cwd);
  const started = performance.now();
  const normalize = text => String(text).replaceAll(cwd, "<workspace>");
  const normalized = value => JSON.parse(normalize(JSON.stringify(value)));
  const record = { id, caseId: test.id, family: test.family, category: test.category, variant: variant.id, repeat,
    trace: [], state: {}, usage: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, totalTokens: 0 }, requests: [], providerEvents: [], text: "" };
  const sessions = new Set();
  let turns = 0; let limited = false;
  const timer = setTimeout(() => { limited = true; for (const session of sessions) void session.conversation.abort(BACKGROUND_CONTEXT); }, suite.config.timeoutMs || 180000);
  const observePayload = payload => {
    const request = { model: payload.model, effort: payload.reasoning?.effort, tier: payload.service_tier,
      tools: payload.tools?.map(tool => tool.name || tool.type), instructionCharacters: payload.instructions?.length,
      instructionsHash: hash(normalize(payload.instructions || "")), sectionsPresent: variant.sections.map(section => payload.instructions?.includes(section) || false) };
    if (request.effort !== (variant.effort === "off" ? "none" : variant.effort) || request.tier !== "priority" ||
      (role !== "coordinator" && !request.tools?.includes("web_search")) || (role === "coordinator" && request.tools?.includes("web_search")))
      throw new Error("Integration provider configuration differs from production");
    record.requests.push({ request });
    record.environment.firstCallSettings ||= request;
    return payload;
  };
  const observeProvider = data => {
    if (!data || typeof data !== "object") return;
    record.providerEvents.push(normalized(data));
    if (data.type === "response.completed") record.requests.at(-1).response = { model: data.response?.model,
      tier: data.response?.service_tier, usage: data.response?.usage, reasoningTokens: data.response?.usage?.output_tokens_details?.reasoning_tokens };
    if (data.type === "response.output_item.done" && data.item?.type === "web_search_call")
      record.trace.push({ role: "tool", name: "web_search", arguments: normalized(data.item.action || {}), text: normalize(JSON.stringify(data.item)) });
  };
  const observed = new Proxy(runtime, { get(target, key) {
    if (key === "streamSimple") return (selected, context, options) => target.streamSimple(selected, context, { ...options,
      onPayload: async (payload, physical) => observePayload(await options.onPayload?.(payload, physical) ?? payload),
      onProviderStreamEvent: async (data, physical) => { await options.onProviderStreamEvent?.(data, physical); observeProvider(data); },
    });
    const value = Reflect.get(target, key);
    return typeof value === "function" ? value.bind(target) : value;
  } });
  const nativeSession = async (customTools = [], acceptedResult) => {
    const loader = agentResources(cwd, role, variant.sections);
    await loader.reload();
    const tools = (role === "session" ? sessionFixtureTools(test, variant) : customTools).map(tool => defineTool({
      name: tool.name, description: tool.description, parameters: tool.parameters,
      execute: async (args, api, context) => {
        const result = await tool.execute(args, api, context);
        return { content: result.content, ...(result.details !== undefined && { details: result.details }),
          ...(acceptedResult?.() && { control: { handoff: "" } }) };
      },
    }));
    const extension = roleExtension(role, tools, variant.sections);
    const boundary = defineExtension({ name: "benchmark-boundary", hooks: [hook(ToolTask, {
      beforeTool: call => {
        const blocked = roleToolBoundary(cwd, test, { toolName: call.name, input: call.arguments });
        if (blocked) record.trace.push({ role: "boundary", name: call.name, arguments: normalized(call.arguments), text: blocked.reason, error: true });
        return blocked ? { block: blocked.reason } : undefined;
      },
    })] });
    const registry = createRegistry(); registry.install(extension); registry.install(boundary);
    const harness = await Harness.open(new MemoryStorage(), { models: providerModels(observed), registry, settings: { toolExecution: "sequential", retry: { enabled: false } } }, BACKGROUND_CONTEXT);
    const conversation = await harness.root(BACKGROUND_CONTEXT, { agent: {
      model: { provider: model.provider, modelId: model.id }, cwd, thinkingLevel: variant.effort, extensions: [extension, boundary],
    } });
    const session = { harness, conversation };
    sessions.add(session);
    const prompt = await extension.sections[0].render({ agent: { cwd } }, BACKGROUND_CONTEXT);
    const skills = loader.getSkills().skills.map(skill => ({ name: skill.name, description: skill.description, path: normalize(skill.filePath), hash: hash(readFileSync(skill.filePath, "utf8")) }));
    const context = loader.getAgentsFiles().agentsFiles.map(file => ({ path: normalize(file.path), hash: hash(file.content) }));
    const fixtureResources = Object.fromEntries(Object.entries(variant.resources || {}).map(([name, content]) => [name, hash(content)]));
    record.environment = { ...record.environment, runtime: "pi-durable", systemPrompt: normalize(prompt), systemPromptHash: hash(normalize(prompt)),
      promptSectionHashes: variant.sections.map(hash), sectionsPresent: variant.sections.map(section => prompt.includes(section)),
      resourceHash: hash({ skills, context, fixtureResources }), fixtureResources, tools: (await conversation.agent(BACKGROUND_CONTEXT)).tools.map(tool => tool.name), skills, context, files: before,
      limitations: role === "session" ? ["Bash executes only exact authored whitelist commands; delegate and computer_use use fixture replies or explicit errors."] :
        role === "coordinator" ? ["HomeRouter discovery uses one new message plus authored state and transcripts; routes are never committed to services."] : [] };
    for (const file of loader.getAgentsFiles().agentsFiles) record.trace.push({ role: "context", name: "project_instructions", text: normalize(file.content), path: normalize(file.path) });
    const callArguments = new Map();
    harness.subscribeCommits(publication => {
      for (const change of publication.changes) {
        if (change.type !== "entry") continue;
        const message = change.value.model?.[0];
        if (message?.role === "assistant") {
          for (const call of message.content.filter(part => part.type === "toolCall")) callArguments.set(call.id, call.arguments);
          recordAssistantMessage(record, message, normalize);
          record.trace.at(-1).calls = normalized(record.trace.at(-1).calls);
          record.trace.at(-1).thinking = normalized(message.content.filter(part => part.type === "thinking"));
          if (++turns >= (suite.config.maxTurns || 8) && !record.completed && !acceptedResult?.()) { limited = true; void conversation.abort(BACKGROUND_CONTEXT); }
        }
        if (message?.role === "toolResult") record.trace.push({ role: "tool", name: message.toolName,
          arguments: normalized(callArguments.get(message.toolCallId) || {}),
          text: normalize(message.content.filter(part => part.type === "text").map(part => part.text).join("\n")), error: message.isError });
      }
    });
    return session;
  };
  try {
    if (role === "coordinator") {
      const data = structuredClone({ messages: [], entries: [], sessions: [], turns: [], ...test.homeState });
      const transcript = sessionId => {
        const file = data.sessions.find(session => session.id === sessionId)?.file;
        const transcript = test.homeState?.transcripts?.[file];
        if (!Array.isArray(transcript)) throw new Error("No authored transcript for the saved conversation");
        return transcript;
      };
      const pi = { utility: async (_role, input, _cwd, tools, acceptedResult) => {
        record.trace.push({ role: "user", text: normalize(input) });
        const session = await nativeSession(tools, acceptedResult);
        try {
          try { await (await session.conversation.submit({ type: "input", content: input }, BACKGROUND_CONTEXT)).wait(BACKGROUND_CONTEXT); }
          catch (error) { if (!acceptedResult()) throw error; }
          const accepted = acceptedResult();
          if (accepted) { record.completed = true; delete record.error; return accepted; }
          if (record.error) throw new Error(record.error);
          if (!record.text) throw new Error("Coordinator returned no answer");
          return record.text;
        } finally { sessions.delete(session); await session.harness.close(BACKGROUND_CONTEXT); }
      } };
      const router = new HomeRouter({ data, transcript }, pi, cwd);
      const routes = [];
      for (const [index, input] of test.messages.entries()) {
        if (input.role !== "user") throw new Error("Native role integration requires user messages, not fabricated assistant history");
        const message = { id: input.id || `benchmark-message-${index}`, text: input.text,
          createdAt: input.createdAt || test.createdAt || "2026-01-01T00:00:00.000Z", entryId: null, status: "routing" };
        if (data.messages.some(item => item.id === message.id)) throw new Error("Home message ID already exists in authored state");
        data.messages.push(message);
        routes.push(await router.discover(message));
        if (limited || record.error) break;
      }
      record.state = { route: normalized(routes.at(-1) || null), routes: normalized(routes) };
      record.text = JSON.stringify(record.state.route);
    } else {
      const session = await nativeSession();
      for (const input of test.messages) {
        if (input.role !== "user") throw new Error("Native role integration requires user messages, not fabricated assistant history");
        record.trace.push({ role: "user", text: normalize(input.text) });
        await (await session.conversation.submit({ type: "input", content: input.text }, BACKGROUND_CONTEXT)).wait(BACKGROUND_CONTEXT);
        if (limited || record.error) break;
      }
    }
    if (limited || !record.completed) record.agentFailure = "Integration turn/time budget exhausted without a final answer";
  } catch (error) {
    if (limited) record.agentFailure = "Integration turn/time budget exhausted without a final answer";
    else record.error = normalize(error.message);
  } finally {
    clearTimeout(timer);
    for (const session of sessions) await session.harness.close(BACKGROUND_CONTEXT);
    try {
      const after = workspaceSnapshot(cwd);
      record.environment ||= {};
      record.environment.filesAfter = after;
      record.state.unchanged = hash(before) === hash(after);
      if (role === "session") record.state.finalFiles = Object.fromEntries(Object.keys(after).map(path => [path, normalize(readFileSync(workspacePath(cwd, path), "utf8"))]));
      if (role === "reviewer" && !record.state.unchanged) record.agentFailure = "Read-only reviewer changed workspace files";
    } catch (error) { record.agentFailure = normalize(error.message); }
  }
  record.elapsedMs = performance.now() - started;
  record.deadlineExceeded = record.elapsedMs > (suite.config.deadlineMs || 180000);
  return record;
}
