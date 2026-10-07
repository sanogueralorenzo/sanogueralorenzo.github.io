import assert from "node:assert/strict";
import { test } from "node:test";
import { mkdtempSync, mkdirSync, writeFileSync, symlinkSync, rmSync } from "node:fs";
import { join } from "node:path";
import { tmpdir } from "node:os";
import { roleToolBoundary, runRoleIntegration } from "./role-integration.mjs";

const model = { id: "native-test", name: "Native test", api: "openai-codex-responses", provider: "openai-codex", baseUrl: "https://invalid.example",
  reasoning: true, input: ["text"], contextWindow: 1000000, maxTokens: 10000, cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 } };
const text = text => ({ type: "text", text });
let nextCall = 0;
const call = (name, args = {}) => ({ type: "toolCall", id: `call-${nextCall++}`, name, arguments: args });
const answer = content => ({ role: "assistant", api: model.api, provider: model.provider, model: model.id, content,
  stopReason: content.some(part => part.type === "toolCall") ? "toolUse" : "stop", timestamp: 0,
  usage: { input: 5, output: 2, cacheRead: 1, cacheWrite: 0, totalTokens: 8, cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, total: 0 } } });

// Actual Durable conversations and native tools; only provider responses are synthetic.
function fakeRuntime(answers, contexts = []) {
  let index = 0;
  const runtime = { hasConfiguredAuth: () => true, checkAuth: async () => "test", isUsingOAuth: () => false,
    getPhysicalModel: () => model, getModel: () => model,
    streamSimple: (_model, context, options) => {
      if (options.signal?.aborted) {
        const aborted = { ...answer([]), stopReason: "aborted" };
        return { result: async () => aborted, async *[Symbol.asyncIterator]() { yield { type: "error", reason: "aborted", error: aborted }; } };
      }
      contexts.push(structuredClone(context));
      const result = answers[index++];
      assert.ok(result, "No unexpected provider continuation after a terminal result");
      const strings = value => typeof value === "string" ? [value] : value && typeof value === "object" ? Object.values(value).flatMap(strings) : [];
      const system = context.messages.filter(message => message.role === "system");
      const tools = system.flatMap(message => message.toolsAdded || []);
      return { result: async () => result, async *[Symbol.asyncIterator]() {
        await options.onPayload({ model: model.id, reasoning: { effort: options.reasoning === "off" ? "none" : options.reasoning },
          instructions: strings(system).join("\n"), tools: tools.map(tool => ({ type: "function", name: tool.name })) });
        await options.onProviderStreamEvent?.({ type: "response.completed", response: { model: model.id, service_tier: "priority",
          usage: { input_tokens: 6, output_tokens: 2, output_tokens_details: { reasoning_tokens: 1 } } } }, model);
        yield { type: "done", reason: result.stopReason, message: result };
      } };
    } };
  return runtime;
}

function workspace(t) {
  const dir = mkdtempSync(join(tmpdir(), "native-role-test-"));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  return dir;
}
function job(testCase = {}, effort = "high") {
  return { id: "trial", repeat: 1, variant: { id: "candidate", effort, resources: {}, sections: ["BASE_SECTION_MARKER", "ROLE_SECTION_MARKER"] },
    test: { id: "native-case", family: "native-family", category: "normal", messages: [{ role: "user", text: "Do the assigned task." }], ...testCase } };
}
const suite = role => ({ config: { mode: "agent", execution: "role-integration", role, maxTurns: 12, timeoutMs: 15000 } });

test("workspace boundary rejects escaping, tilde, symlink paths and non-exact bash commands", t => {
  const cwd = workspace(t);
  const outside = workspace(t);
  mkdirSync(join(cwd, "src"));
  writeFileSync(join(outside, "private.txt"), "private");
  symlinkSync(outside, join(cwd, "escape"));
  const event = path => ({ toolName: "read", input: { path } });
  for (const path of ["../private.txt", "@../private.txt", "~/private.txt", join(outside, "private.txt"), "escape/private.txt", "escape/new.txt"])
    assert.equal(roleToolBoundary(cwd, {}, event(path))?.block, true, path);
  assert.equal(roleToolBoundary(cwd, {}, event("src/new.txt"))?.block, true, "Reject symlink-bearing workspaces even for unrelated paths");
  const bash = command => ({ toolName: "bash", input: { command } });
  assert.equal(roleToolBoundary(cwd, { allowedCommands: ["pwd"] }, bash("pwd; touch escaped"))?.block, true);
  assert.equal(roleToolBoundary(cwd, {}, bash("pwd"))?.block, true);
  assert.equal(roleToolBoundary(cwd, { allowedCommands: ["pwd"] }, bash("pwd"))?.block, true, "Bash cannot run while workspace contains a symlink");
  rmSync(join(cwd, "escape"));
  assert.equal(roleToolBoundary(cwd, {}, event("src/new.txt")), undefined);
  assert.equal(roleToolBoundary(cwd, { allowedCommands: ["pwd"] }, bash("pwd")), undefined);
});

test("reviewer uses actual read/search tools and loaded resources with both candidate sections", async t => {
  const contexts = [];
  const result = await runRoleIntegration(fakeRuntime([
    answer([call("read", { path: "src/cache.js" }), call("grep", { pattern: "ttl", path: "src" }), call("find", { pattern: "*.js", path: "src" }), call("ls", { path: "src" })]),
    answer([text("src/cache.js sets ttl to 5.")]),
  ], contexts), model, suite("reviewer"), job({ files: {
    "AGENTS.md": "Use LOCAL_RESOURCE_MARKER.", "src/cache.js": "export const ttl = 5;\n",
    ".pi/skills/cache/SKILL.md": "---\nname: cache\ndescription: Explain caching\n---\nRead src/cache.js.\n",
  } }), { workspaceDir: workspace(t) });
  assert.equal(result.error, undefined);
  assert.equal(result.completed, true);
  assert.equal(result.state.unchanged, true);
  assert.deepEqual(result.environment.tools, ["read", "grep", "find", "ls"]);
  assert.deepEqual(result.environment.sectionsPresent, [true, true]);
  assert.match(result.environment.systemPrompt, /LOCAL_RESOURCE_MARKER/);
  assert.ok(result.environment.context.some(file => file.path === "<workspace>/AGENTS.md"));
  assert.ok(result.environment.skills.some(skill => skill.name === "cache" && skill.hash));
  assert.equal(result.environment.systemPromptHash.length, 64);
  assert.equal(result.requests.length, 2);
  assert.equal(result.requests[0].usage.totalTokens, 8);
  assert.equal(result.requests[0].response.reasoningTokens, 1);
  assert.equal(result.usage.totalTokens, 16);
  assert.deepEqual(result.environment.firstCallSettings.sectionsPresent, [true, true]);
  assert.ok(result.trace.some(entry => entry.role === "tool" && entry.name === "read" && entry.text.includes("ttl = 5")));
  assert.equal(JSON.stringify(result).includes("native-role-test-"), false);
  assert.equal(contexts.length, 2);
});

test("session final artifacts reflect native writes and edits, not completion claims", async t => {
  const config = suite("session");
  const saved = await runRoleIntegration(fakeRuntime([
    answer([call("write", { path: "report.json", content: '{"release":"old"}\n' })]),
    answer([call("edit", { path: "report.json", edits: [{ oldText: "old", newText: "new" }] })]),
    answer([call("read", { path: "report.json" })]),
    answer([text("Saved report.json.")]),
  ]), model, config, job(), { workspaceDir: workspace(t) });
  const claimed = await runRoleIntegration(fakeRuntime([answer([text("Saved report.json.")])]), model, config, job(), { workspaceDir: workspace(t) });
  assert.equal(saved.error, undefined);
  assert.equal(saved.state.finalFiles["report.json"], '{"release":"new"}\n');
  assert.equal(saved.state.unchanged, false);
  assert.equal(claimed.completed, true);
  assert.deepEqual(claimed.state.finalFiles, {});
  assert.equal(claimed.state.unchanged, true);
});

test("native session blocks outside writes and non-whitelisted bash; allowed bash executes", async t => {
  const result = await runRoleIntegration(fakeRuntime([
    answer([call("write", { path: "../outside.txt", content: "bad" }), call("bash", { command: "touch forbidden.txt" })]),
    answer([call("bash", { command: "printf verified > verification.txt" })]),
    answer([text("Checks complete.")]),
  ]), model, suite("session"), job({ allowedCommands: ["printf verified > verification.txt"] }), { workspaceDir: workspace(t) });
  assert.equal(result.error, undefined);
  assert.deepEqual(result.state.finalFiles, { "verification.txt": "verified" });
  assert.equal(result.trace.filter(entry => entry.role === "boundary").length, 2);
  assert.ok(result.trace.some(entry => entry.name === "bash" && entry.error));
});

test("session external tools return explicit errors or authored fixture replies without external actions", async t => {
  const result = await runRoleIntegration(fakeRuntime([
    answer([call("computer_use", { code: "await cua.getState();" }), call("delegate", { role: "researcher", task: "Read the cache" })]),
    answer([text("Research complete; computer access unavailable.")]),
  ]), model, suite("session"), job({ fixtures: [{ tool: "delegate", match: { role: "researcher" }, response: "Authored cache evidence." }] }), { workspaceDir: workspace(t) });
  assert.equal(result.error, undefined);
  assert.ok(result.trace.some(entry => entry.name === "computer_use" && entry.error && entry.text.includes("disabled")));
  assert.ok(result.trace.some(entry => entry.name === "delegate" && !entry.error && entry.text === "Authored cache evidence."));
  assert.equal(result.state.unchanged, true);
});

test("coordinator uses production HomeRouter discovery tools/context and stops at accepted route", async t => {
  const contexts = [];
  const sessions = Array.from({ length: 13 }, (_, index) => ({ id: `saved-${index}`, title: index === 0 ? "Historic cache work" : `Recent work ${index}`,
    cwd: "<workspace>", file: `saved-file-${index}`, status: "idle", createdAt: `2026-01-${String(index + 1).padStart(2, "0")}T00:00:00.000Z` }));
  const result = await runRoleIntegration(fakeRuntime([
    answer([call("find_conversations", { query: "historic cache" })]),
    answer([call("read_conversation", { sessionId: "saved-0" })]),
    answer([call("route_home", { mode: "continue", sessionId: "saved-0" })]),
  ], contexts), model, suite("coordinator"), job({ files: { "AGENTS.md": "COORDINATOR_CONTEXT_MUST_BE_OMITTED" },
    createdAt: "2026-02-01T00:00:00.000Z", messages: [{ role: "user", text: "Resume the historic cache work." }],
    homeState: { sessions, entries: [{ id: "entry", sessionId: "saved-12", sourceId: "previous", createdAt: "2026-01-31T00:00:00.000Z", updatedAt: "2026-01-31T00:00:00.000Z",
      updates: [{ kind: "result", sourceId: "previous", text: "Saved a cache draft.", createdAt: "2026-01-31T00:00:00.000Z" }] }],
    messages: [{ id: "previous", entryId: "entry", text: "Write the cache draft.", createdAt: "2026-01-31T00:00:00.000Z" }],
    transcripts: { "saved-file-0": [{ role: "user", text: "Historic cache research." }, { role: "assistant", text: "Cache draft ready." }] } },
  }, "low"), { workspaceDir: workspace(t) });
  assert.equal(result.error, undefined);
  assert.equal(result.completed, true);
  assert.deepEqual(result.state.route, { mode: "continue", sessionId: "saved-0" });
  assert.equal(result.state.unchanged, true);
  assert.deepEqual(result.environment.tools, ["find_conversations", "read_conversation", "route_home"]);
  assert.deepEqual(result.environment.context, []);
  assert.deepEqual(result.environment.skills, []);
  assert.equal(result.environment.firstCallSettings.effort, "low");
  assert.equal(result.environment.firstCallSettings.tools.includes("web_search"), false);
  assert.equal(result.environment.systemPrompt.includes("COORDINATOR_CONTEXT_MUST_BE_OMITTED"), false);
  const input = result.trace.find(entry => entry.role === "user").text;
  assert.match(input, /Most recent Home exchange:.*Write the cache draft.*Saved a cache draft/s);
  assert.match(input, /Original user message \(verbatim\):\nResume the historic cache work/);
  assert.match(input, /Current workspace: <workspace>/);
  assert.match(input, /"cwd":"<workspace>"/);
  assert.ok(result.trace.some(entry => entry.name === "find_conversations" && entry.text.includes("saved-0")));
  assert.ok(result.trace.some(entry => entry.name === "read_conversation" && entry.text.includes("Cache draft ready")));
  assert.ok(result.trace.some(entry => entry.name === "route_home" && entry.text === "Destination accepted."));
  assert.equal(contexts.length, 3);
});

test("coordinator rejects unsupported consecutive Home messages instead of approximating committed state", async () => {
  await assert.rejects(runRoleIntegration(fakeRuntime([]), model, suite("coordinator"), job({ messages: [
    { role: "user", text: "Start cache work." }, { role: "user", text: "Continue it." },
  ] }, "low")), /one new Home message per case/);
});
