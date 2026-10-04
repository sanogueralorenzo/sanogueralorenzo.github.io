import { readFileSync, writeFileSync, mkdirSync, mkdtempSync, readdirSync, lstatSync } from "node:fs";
import { join, dirname, relative, resolve, sep } from "node:path";
import { tmpdir } from "node:os";
import { createAgentSession, SessionManager, defineTool } from "@earendil-works/pi-coding-agent";
import { Type } from "typebox";
import { agentResources, agentToolNames, providerTools } from "../../src/agent-resources.ts";
import { HomeRouter } from "../../src/home-routing.ts";
import { ComputerUseClient } from "../../src/computer-use.ts";
import { workspacePath, workspaceSnapshot, recordAssistantMessage } from "./researcher-integration.mjs";
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
    execute: async (_id, args) => {
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
  if (!["reviewer", "session", "coordinator"].includes(role)) throw new Error("Role integration requires reviewer, session, or coordinator");
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
  const timer = setTimeout(() => { limited = true; for (const session of sessions) void session.abort(); }, suite.config.timeoutMs || 180000);
  const observer = pi => {
    pi.on("tool_call", event => {
      const blocked = roleToolBoundary(cwd, test, event);
      if (blocked) record.trace.push({ role: "boundary", name: event.toolName, arguments: normalized(event.input), text: blocked.reason, error: true });
      return blocked;
    });
    pi.on("before_provider_request", ({ payload }) => {
      const request = { model: payload.model, effort: payload.reasoning?.effort, tier: payload.service_tier,
        tools: payload.tools?.map(tool => tool.name || tool.type), instructionCharacters: payload.instructions?.length,
        instructionsHash: hash(normalize(payload.instructions || "")), sectionsPresent: variant.sections.map(section => payload.instructions?.includes(section) || false) };
      if (request.effort !== (variant.effort === "off" ? "none" : variant.effort) || request.tier !== "priority" ||
        (role !== "coordinator" && !request.tools?.includes("web_search")) || (role === "coordinator" && request.tools?.includes("web_search")))
        throw new Error("Integration provider configuration differs from production");
      record.requests.push({ request });
      record.environment.firstCallSettings ||= request;
    });
    pi.on("provider_stream_event", ({ data }) => {
      if (!data || typeof data !== "object") return;
      record.providerEvents.push(normalized(data));
      if (data.type === "response.completed") record.requests.at(-1).response = { model: data.response?.model,
        tier: data.response?.service_tier, usage: data.response?.usage, reasoningTokens: data.response?.usage?.output_tokens_details?.reasoning_tokens };
      if (data.type === "response.output_item.done" && data.item?.type === "web_search_call")
        record.trace.push({ role: "tool", name: "web_search", arguments: normalized(data.item.action || {}), text: normalize(JSON.stringify(data.item)) });
    });
  };
  const nativeSession = async (customTools = [], acceptedResult) => {
    const loader = agentResources(cwd, role, [providerTools(role, () => {}), observer], variant.sections);
    await loader.reload();
    const tools = role === "session" ? sessionFixtureTools(test, variant) : customTools;
    const { session } = await createAgentSession({ cwd, modelRuntime: runtime, model, thinkingLevel: variant.effort,
      resourceLoader: loader, sessionManager: SessionManager.inMemory(cwd), customTools: tools, tools: agentToolNames(role, tools.map(tool => tool.name)) });
    sessions.add(session);
    const skills = loader.getSkills().skills.map(skill => ({ name: skill.name, description: skill.description, path: normalize(skill.filePath), hash: hash(readFileSync(skill.filePath, "utf8")) }));
    const context = loader.getAgentsFiles().agentsFiles.map(file => ({ path: normalize(file.path), hash: hash(file.content) }));
    const fixtureResources = Object.fromEntries(Object.entries(variant.resources || {}).map(([name, content]) => [name, hash(content)]));
    record.environment = { ...record.environment, systemPrompt: normalize(session.systemPrompt), systemPromptHash: hash(normalize(session.systemPrompt)),
      promptSectionHashes: variant.sections.map(hash), sectionsPresent: variant.sections.map(section => session.systemPrompt.includes(section)),
      resourceHash: hash({ skills, context, fixtureResources }), fixtureResources, tools: session.getActiveToolNames(), skills, context, files: before,
      limitations: role === "session" ? ["Bash executes only exact authored whitelist commands; delegate and computer_use use fixture replies or explicit errors."] :
        role === "coordinator" ? ["HomeRouter discovery uses one new message plus authored in-memory state and transcripts; routes are never committed to sessions or services."] : [] };
    for (const file of loader.getAgentsFiles().agentsFiles) record.trace.push({ role: "context", name: "project_instructions", text: normalize(file.content), path: normalize(file.path) });
    const callArguments = new Map();
    session.subscribe(event => {
      if (event.type === "tool_execution_start") callArguments.set(event.toolCallId, event.args);
      if (event.type === "message_end" && event.message.role === "assistant") {
        recordAssistantMessage(record, event.message, normalize);
        record.trace.at(-1).calls = normalized(record.trace.at(-1).calls);
        record.trace.at(-1).thinking = normalized(event.message.content.filter(part => part.type === "thinking"));
        if (++turns >= (suite.config.maxTurns || 8) && !record.completed && !acceptedResult?.()) { limited = true; void session.abort(); }
      }
      if (event.type === "tool_execution_end") {
        record.trace.push({ role: "tool", name: event.toolName, arguments: normalized(callArguments.get(event.toolCallId) || {}),
          text: normalize((event.result?.content || []).filter(part => part.type === "text").map(part => part.text).join("\n")), error: event.isError });
        if (acceptedResult?.()) void session.abort();
      }
    });
    return session;
  };
  try {
    if (role === "coordinator") {
      const data = structuredClone({ messages: [], entries: [], sessions: [], turns: [], ...test.homeState });
      const pi = { transcript: file => {
        const transcript = test.homeState?.transcripts?.[file];
        if (!Array.isArray(transcript)) throw new Error("No authored transcript for the saved conversation");
        return transcript;
      }, utility: async (_role, input, _cwd, tools, acceptedResult) => {
        record.trace.push({ role: "user", text: normalize(input) });
        const session = await nativeSession(tools, acceptedResult);
        try {
          try { await session.prompt(input, { expandPromptTemplates: false }); }
          catch (error) { if (!acceptedResult()) throw error; }
          const accepted = acceptedResult();
          if (accepted) { record.completed = true; delete record.error; return accepted; }
          if (record.error) throw new Error(record.error);
          if (!record.text) throw new Error("Coordinator returned no answer");
          return record.text;
        } finally { sessions.delete(session); session.dispose(); }
      } };
      const router = new HomeRouter({ data }, pi, cwd);
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
        await session.prompt(input.text, { expandPromptTemplates: false });
        if (limited || record.error) break;
      }
    }
    if (limited || !record.completed) record.agentFailure = "Integration turn/time budget exhausted without a final answer";
  } catch (error) {
    if (limited) record.agentFailure = "Integration turn/time budget exhausted without a final answer";
    else record.error = normalize(error.message);
  } finally {
    clearTimeout(timer);
    for (const session of sessions) session.dispose();
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
