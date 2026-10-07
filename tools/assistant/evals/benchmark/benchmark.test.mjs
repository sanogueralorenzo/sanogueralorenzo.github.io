import assert from "node:assert/strict";
import { test } from "node:test";
import { mkdtempSync, writeFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { loadSuite, schedule } from "./suite.mjs";
import { runTrial } from "./trial.mjs";
import { checks, blindCards, validateReviews } from "./grading.mjs";
import { pairedInterval } from "./statistics.mjs";

const answer = content => ({ role: "assistant", content, stopReason: content.some(p => p.type === "toolCall") ? "toolUse" : "stop", usage: { input: 5, output: 2, totalTokens: 7 }, timestamp: 0 });
function fakeRuntime(answers, contexts = []) {
  let index = 0;
  return { streamSimple: (_model, context, options) => {
    contexts.push(structuredClone(context));
    options.onPayload({ model: "test", reasoning: { effort: options.reasoning === "off" ? "none" : options.reasoning } });
    const value = answers[index++];
    return { async *[Symbol.asyncIterator]() {}, result: async () => value };
  } };
}
const text = value => ({ type: "text", text: value });
const call = (name, args = {}) => ({ type: "toolCall", id: name, name, arguments: args });

test("confirmation rejects reused families and instruction/resource hashes change", t => {
  const dir = mkdtempSync(join(tmpdir(), "instruction-benchmark-"));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  const caseOf = (id, family) => ({ id, family, category: "normal", rubric: "Do the requested work", messages: [{ role: "user", text: id }] });
  const put = (file, value) => writeFileSync(join(dir, file), typeof value === "string" ? value : JSON.stringify(value));
  put("dev.json", [caseOf("one", "first")]); put("confirm.json", [caseOf("two", "first")]); put("prompt.md", "Predict."); put("skill.md", "Read the source.");
  put("suite.json", { id: "test", mode: "suggestion", effort: "off", datasets: { development: ["dev.json"], confirmation: ["confirm.json"] }, variants: [{ id: "base", files: ["prompt.md"], resources: { skill: "skill.md" } }] });
  assert.throws(() => loadSuite(join(dir, "suite.json"), "development"), /Confirmation family reused/);
  put("confirm.json", [caseOf("two", "second")]);
  const first = loadSuite(join(dir, "suite.json"), "development");
  put("skill.md", "Read and verify the source.");
  const second = loadSuite(join(dir, "suite.json"), "development");
  assert.notEqual(first.fingerprint, second.fingerprint);
  assert.notEqual(first.variants[0].hash, second.variants[0].hash);
});

test("paired schedule repeats every case and rotates variant position", () => {
  const jobs = schedule([{ id: "a" }, { id: "b" }], [{ id: "base" }, { id: "short" }], 3);
  assert.equal(jobs.length, 12); assert.equal(new Set(jobs.map(j => j.id)).size, 12);
  assert.deepEqual(jobs.slice(0, 4).map(j => j.variant.id), ["base", "short", "short", "base"]);
  assert.throws(() => schedule([], [], 0), /positive integer/);
});

test("fixture loop verifies outcome instead of completion claims and isolates each trial", async () => {
  const fixture = { id: "a", family: "a", category: "work", messages: [{ role: "user", text: "Save the report" }], tools: [{ name: "write", parameters: {} }], initialState: { report: "old" }, fixtures: [{ tool: "write", match: { path: "report.json" }, response: "saved", effects: { report: { argument: "content" } } }], checks: [{ type: "state", value: { report: "new" } }] };
  const suite = { config: { mode: "agent", maxTurns: 3 } };
  const variant = { id: "base", prompt: "Complete work", effort: "high", resources: {} };
  const contexts = [];
  const good = await runTrial(fakeRuntime([answer([call("write", { path: "report.json", content: "new" })]), answer([text("Saved.")])], contexts), {}, suite, { id: "good", test: fixture, variant, repeat: 1 });
  const claimed = await runTrial(fakeRuntime([answer([text("Saved.")])]), {}, suite, { id: "claim", test: fixture, variant, repeat: 2 });
  assert.equal(good.state.report, "new"); assert.equal(claimed.state.report, "old"); assert.equal(fixture.initialState.report, "old");
  assert.ok(checks(good, fixture, "agent").every(c => c.ok)); assert.ok(checks(claimed, fixture, "agent").some(c => !c.ok));
  assert.equal(contexts[1].messages.at(-1).role, "toolResult"); assert.equal(good.usage.totalTokens, 14);
  assert.equal(good.requests[0].usage.input, 5);
  assert.equal(good.requests[0].usage.totalTokens, 7);
});

test("unknown tools cannot mutate fixture state and exhausted agent budgets remain gradeable", async () => {
  const fixture = { id: "a", family: "a", category: "work", messages: [{ role: "user", text: "Read" }], tools: [{ name: "read", parameters: {} }], fixtures: [{ tool: "write", response: "saved", effects: { file: "bad" } }] };
  const record = await runTrial(fakeRuntime([answer([call("write")])]), {}, { config: { mode: "agent", maxTurns: 1 } }, { id: "bad", test: fixture, variant: { id: "base", prompt: "Read only", effort: "off", resources: {} }, repeat: 1 });
  assert.equal(record.state.file, undefined); assert.equal(record.error, undefined); assert.ok(record.agentFailure);
  assert.ok(checks(record, fixture, "agent").some(c => c.kind === "outcome" && !c.ok));
});

test("blind cards hide variants, usage, and instruction resources; review completeness is enforced", () => {
  const run = { fingerprint: "fingerprint", mode: "agent", cases: [{ id: "a", messages: [], rubric: "Finish" }], variants: [{ id: "secret-long", resources: { skill: "candidate instructions" } }], results: [{ id: "trial", caseId: "a", variant: "secret-long", text: "Done", state: {}, usage: { input: 100 }, trace: [{ role: "tool", text: "candidate instructions" }] }] };
  const cards = blindCards(run);
  assert.ok(!JSON.stringify(cards).includes("secret-long")); assert.ok(!JSON.stringify(cards).includes("candidate instructions")); assert.ok(!JSON.stringify(cards).includes('"usage"'));
  assert.throws(() => validateReviews(cards, []), /Every successful trial/);
  const review = { id: cards[0].id, utility: "useful", constraints: "preserved", confidence: "high", note: "Observed outcome matches" };
  assert.equal(validateReviews(cards, [review]).length, 1);
  assert.throws(() => validateReviews(cards, [review, review]), /duplicate/);
});

test("paired intervals cluster repeats and related cases rather than inflate independent tasks", () => {
  const rows = [];
  for (const family of ["one", "two"]) for (let repeat = 0; repeat < 20; repeat++) for (const variant of ["base", "short"]) rows.push({ family, caseId: family, variant, score: variant === "short" ? 1 : 2 });
  const result = pairedInterval(rows, "base", "short", 100);
  assert.equal(result.pairedFamilies, 2); assert.equal(result.meanDifference, -1); assert.equal(result.low, -1); assert.equal(result.high, -1);
});

test('rejected tool arguments cannot change state or end a trial', async () => {
  const fixture = { id: 'route', family: 'route', category: 'routing', messages: [{ role: 'user', text: 'Route' }], tools: [{ name: 'route', parameters: {} }], fixtures: [{ tool: 'route', response: 'accepted', validate: [{ key: 'sessionId', type: 'enum', values: ['known'], message: 'Use a known ID' }], effects: { destination: { argument: 'sessionId' } }, terminal: true }] };
  const record = await runTrial(fakeRuntime([answer([call('route', { sessionId: 'invented' })]), answer([call('route', { sessionId: 'known' })])]), {}, { config: { mode: 'agent', maxTurns: 2 } }, { id: 'trial', test: fixture, variant: { id: 'base', prompt: 'Route', effort: 'low', resources: {} }, repeat: 1 });
  assert.equal(record.trace[1].error, true); assert.equal(record.state.destination, 'known'); assert.equal(record.completed, true);
});

test('exact JSON and prohibited argument checks catch extra keys and out-of-scope writes', () => {
  const record = { text: '', state: { card: '{"release":"2","secret":"extra"}' }, trace: [{ role: 'tool', name: 'write', arguments: { path: 'other.json' } }] };
  const test = { checks: [{ type: 'json', stateKey: 'card', value: { release: '2' }, exact: true }, { type: 'noTool', names: ['write'], arguments: { path: 'other.json' } }, { type: 'absent', keys: ['cwd'] }] };
  assert.deepEqual(checks(record, test, 'agent').map(c => c.ok), [false, false, true]);
});

test('reports reject mismatched reviews and cannot promote uncertain or development evidence', async () => {
  const { makeReport } = await import('./artifacts.mjs'); const { hash } = await import('./suite.mjs');
  const run = { complete: true, fingerprint: 'f', suite: 'test', split: 'development', mode: 'suggestion', selection: { maxMeanUtilityLoss: .1, minTotalTokenSavingPercent: 10, requireZeroNewConstraintViolations: true }, cases: [{ id: 'a', messages: [], rubric: 'Suggest' }], variants: [{ id: 'base', resources: {} }, { id: 'short', resources: {} }], results: ['base','short'].map(variant => ({ id: variant, variant, caseId: 'a', family: 'a', text: 'NONE', trace: [], state: {}, elapsedMs: 1, usage: { input: variant === 'base' ? 100 : 50, output: 1, cacheRead: 0, totalTokens: variant === 'base' ? 101 : 51 } })) };
  const artifact = { inputHash: hash(run), provenance: 'Test reviewer', reviews: blindCards(run).map(c => ({ id: c.id, utility: 'useful', constraints: 'preserved', confidence: 'high', note: 'Appropriate abstention' })) };
  assert.throws(() => makeReport(run, { ...artifact, inputHash: 'other' }), /matching/);
  assert.equal(makeReport(run, artifact).selection.short.status, 'not-established');
  run.split = 'confirmation'; artifact.inputHash = hash(run);
  assert.equal(makeReport(run, artifact).selection.short.status, 'meets-local-gate');
  run.selection.minPairedFamilyMeanUtilityGain = .05;
  artifact.inputHash = hash(run);
  assert.equal(makeReport(run, artifact).selection.short.status, 'not-established', 'large token savings cannot replace a required quality gain');
  delete run.selection.minPairedFamilyMeanUtilityGain;
  artifact.inputHash = hash(run);
  artifact.reviews[0].confidence = 'low';
  assert.equal(makeReport(run, artifact).selection.short.status, 'not-established');
});

test('frozen confirmation refuses changed inputs before authentication or model calls', async t => {
  const { execFileSync } = await import('node:child_process');
  const dir = mkdtempSync(join(tmpdir(), 'benchmark-freeze-'));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  const put = (file, value) => writeFileSync(join(dir, file), typeof value === 'string' ? value : JSON.stringify(value));
  const fixture = id => ({ id, family: id, category: 'normal', rubric: 'Predict', messages: [{ role: 'user', text: id }] });
  put('dev.json', [fixture('dev')]); put('confirmation.json', [fixture('confirm')]); put('prompt.md', 'Predict.');
  put('suite.json', { id: 'freeze', mode: 'suggestion', effort: 'off', datasets: { development: ['dev.json'], confirmation: ['confirmation.json'] }, variants: [{ id: 'base', files: ['prompt.md'] }] });
  const cli = new URL('./cli.mjs', import.meta.url).pathname;
  const args = [cli, 'freeze', join(dir,'suite.json'), '--split', 'confirmation', '--out', join(dir,'freeze.json')];
  execFileSync(process.execPath, ['--experimental-strip-types', ...args], { stdio: 'pipe' });
  put('prompt.md', 'Changed instructions.');
  assert.throws(() => execFileSync(process.execPath, ['--experimental-strip-types', cli, 'run', join(dir,'suite.json'), '--split', 'confirmation', '--freeze', join(dir,'freeze.json'), '--out', join(dir,'run.json')], { stdio: 'pipe' }), /Frozen manifest differs/);
});

test('explicit infrastructure retry preserves failed attempts and never retries semantic failures', async t => {
  const { execFileSync } = await import('node:child_process'); const { hash, readJSON } = await import('./suite.mjs');
  const dir = mkdtempSync(join(tmpdir(), 'benchmark-retry-'));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  const put = (file, value) => writeFileSync(join(dir,file), typeof value === 'string' ? value : JSON.stringify(value));
  put('cases.json', [{ id: 'a', family: 'a', category: 'normal', rubric: 'Predict', messages: [] }]); put('prompt.md', 'Predict.');
  put('suite.json', { id: 'retry', mode: 'suggestion', effort: 'off', datasets: { development: ['cases.json'] }, variants: [{ id: 'base', files: ['prompt.md'] }] });
  const suite = loadSuite(join(dir,'suite.json'), 'development');
  const run = { split: 'development', repeats: 3, concurrency: 2, variants: [{ id: 'base' }], fingerprint: hash({ suite: suite.fingerprint, variants: ['base'], repeats: 3, concurrency: 2 }), results: [{ id: 'infra', error: 'Temporary limit' }, { id: 'semantic', text: 'Wrong action', agentFailure: 'Turn limit' }] };
  put('run.json',run);
  execFileSync(process.execPath, ['--experimental-strip-types',new URL('./retry.mjs',import.meta.url).pathname,join(dir,'suite.json'),join(dir,'run.json')], { stdio: 'pipe' });
  const repaired = readJSON(join(dir,'run.json'));
  assert.deepEqual(repaired.results, [run.results[1]]); assert.deepEqual(repaired.infrastructureRetries[0].failures, [run.results[0]]);
  assert.equal(repaired.infrastructureRetries[0].sourceHash, hash(run));
});

test('read-after-write uses current isolated state and schema validation checks the actual artifact', async () => {
  const fixture = { id: 'card', family: 'card', category: 'artifact', messages: [{ role: 'user', text: 'Update' }], tools: [{ name: 'read', parameters: {} }, { name: 'write', parameters: {} }, { name: 'validate', parameters: {} }], initialState: { card: '{"release":"1","note":"Keep"}' }, fixtures: [{ tool: 'read', stateKey: 'card', response: 'Missing' }, { tool: 'write', response: 'Saved', effects: { card: { argument: 'content' } } }, { tool: 'validate', validateJSON: { stateKey: 'card', keys: ['release','note'], types: { release: 'string', note: 'string' } }, response: 'Valid', effects: { verified: true } }] };
  const variant = { id: 'base', prompt: 'Update', effort: 'high', resources: {} }, suite = { config: { mode: 'agent', maxTurns: 5 } };
  const value = '{"release":"2","note":"Keep"}';
  const record = await runTrial(fakeRuntime([answer([call('write', { content: value })]), answer([call('read')]), answer([call('validate')]), answer([text('Verified.')])]), {}, suite, { id: 'good', test: fixture, variant, repeat: 1 });
  assert.equal(record.trace.find(t => t.name === 'read').text, value); assert.equal(record.state.verified, true);
  const invalid = await runTrial(fakeRuntime([answer([call('write', { content: '{"release":"2","note":"Keep","extra":1}' })]), answer([call('validate')]), answer([text('Validation failed.')])]), {}, suite, { id: 'bad', test: fixture, variant, repeat: 1 });
  assert.equal(invalid.state.verified, undefined); assert.equal(invalid.trace.find(t => t.name === 'validate').error, true);
  assert.equal(fixture.initialState.card, '{"release":"1","note":"Keep"}');
});

test('renaming duplicated confirmation inputs cannot bypass split isolation', t => {
  const dir = mkdtempSync(join(tmpdir(), 'benchmark-leak-')); t.after(() => rmSync(dir, { recursive: true, force: true }));
  const put = (file, value) => writeFileSync(join(dir,file), typeof value === 'string' ? value : JSON.stringify(value));
  const fixture = { id: 'dev', family: 'dev', category: 'normal', rubric: 'Answer', messages: [{ role: 'user', text: 'Identical request' }] };
  put('dev.json',[fixture]); put('confirm.json',[{...fixture,id:'new-id',family:'new-family'}]); put('prompt.md','Answer.');
  put('suite.json',{id:'leak',mode:'agent',effort:'high',datasets:{development:['dev.json'],confirmation:['confirm.json']},variants:[{id:'base',files:['prompt.md']}]});
  assert.throws(() => loadSuite(join(dir,'suite.json'),'development'),/Confirmation input reused/);
});

test('exact JSON compares nested arrays and explicit workflow order is observed', () => {
  const record = { text: '', state: { card: '{"items":["one","two","extra"]}' }, trace: [{ role: 'tool', name: 'validate', arguments: { path: 'card' } }, { role: 'tool', name: 'write', arguments: { path: 'card' } }] };
  const test = { checks: [{ type: 'json', stateKey: 'card', value: { items: ['one','two'] }, exact: true }, { type: 'toolOrder', before: { name: 'write' }, after: { name: 'validate' }, position: 'last' }] };
  assert.deepEqual(checks(record,test,'agent').map(c => c.ok),[false,false]);
  record.trace.push({ role: 'tool', name: 'validate', arguments: { path: 'card' } });
  assert.equal(checks(record,test,'agent')[1].ok,true);
});

test('uncertain tasks are not scored as wrong and invalid assertions are waived across the whole case', async () => {
  const { makeReport } = await import('./artifacts.mjs'); const { hash } = await import('./suite.mjs');
  const run = { complete: true, fingerprint: 'f', suite: 'test', split: 'confirmation', mode: 'agent', cases: [{ id: 'a', messages: [], rubric: 'User override', checks: [{ type: 'tool', name: 'superseded' }] }], variants: [{ id: 'base', resources: {} }, { id: 'short', resources: {} }], results: ['base','short'].map(variant => ({ id: variant, variant, caseId: 'a', family: 'a', text: 'Done', trace: [], state: {}, elapsedMs: 1, usage: { input: 100, output: 1, cacheRead: 0, totalTokens: 101 } })) };
  const artifact = { inputHash: hash(run), provenance: 'Audit', reviews: blindCards(run).map(c => ({ id: c.id, utility: 'uncertain', constraints: 'preserved', confidence: 'low', note: 'Missing evidence' })) };
  const uncertain = makeReport(run,artifact);
  assert.equal(uncertain.metrics.base.meanUtility,null); assert.equal(uncertain.metrics.base.wrong,0); assert.equal(uncertain.comparisons.short.pairedFamilies,0);
  artifact.reviews.forEach(r => {r.utility='useful';r.confidence='high';});
  artifact.checkWaivers=[{caseId:'a',index:0,reason:'User explicitly supersedes this workflow step.',provenance:'Whole-family audit'}];
  const waived=makeReport(run,artifact);
  assert.equal(waived.metrics.base.deterministicFailures,0); assert.equal(waived.metrics.short.deterministicFailures,0);
  artifact.checkWaivers[0].index=2;
  assert.throws(()=>makeReport(run,artifact),/known case/);
});

test('the first accepted terminal action prevents later calls from changing its outcome', async () => {
  const fixture={id:'route',family:'route',category:'route',messages:[],tools:[{name:'route',parameters:{}}],fixtures:[{tool:'route',response:'Accepted',terminal:true,effects:{destination:{argument:'id'}}}]};
  const record=await runTrial(fakeRuntime([answer([call('route',{id:'first'}),call('route',{id:'second'})])]),{}, {config:{mode:'agent',maxTurns:1}}, {id:'terminal',test:fixture,variant:{id:'base',prompt:'Route',effort:'low',resources:{}},repeat:1});
  assert.equal(record.state.destination,'first');assert.equal(record.trace.filter(t=>t.role==='tool').length,1);assert.equal(record.completed,true);
});

test("integration read boundaries match native path prefixes and snapshots detect file changes", async () => {
  const { workspacePath, workspaceSnapshot } = await import("./integration-workspace.mjs");
  const { mkdtempSync, writeFileSync, rmSync } = await import("node:fs");
  const { tmpdir } = await import("node:os");
  const { join } = await import("node:path");
  const root = mkdtempSync(join(tmpdir(), "assistant-integration-test-"));
  try {
    assert.equal(workspacePath(root, "@source.ts"), join(root, "source.ts"));
    for (const path of ["../outside", "~/secrets", "@/etc/passwd", "@../outside"]) assert.throws(() => workspacePath(root, path));
    writeFileSync(join(root, "source.ts"), "one");
    const before = workspaceSnapshot(root);
    writeFileSync(join(root, "source.ts"), "two");
    assert.notDeepEqual(workspaceSnapshot(root), before);
  } finally { rmSync(root, { recursive: true, force: true }); }
});

test("integration records recovered SDK retries and uses the actual production reply renderer", async () => {
  const { recordAssistantMessage } = await import("./integration-workspace.mjs");
  const record = { usage: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, totalTokens: 0 }, trace: [] };
  recordAssistantMessage(record, { role: "assistant", content: [], stopReason: "error", errorMessage: "WebSocket error" });
  assert.equal(record.error, "WebSocket error");
  recordAssistantMessage(record, { role: "assistant", content: [{ type: "text", text: "Source unavailable. ([]())" }], stopReason: "stop", usage: { input: 4, output: 3, totalTokens: 7 } });
  assert.equal(record.error, undefined);
  assert.deepEqual(record.providerErrors, ["WebSocket error"]);
  assert.equal(record.text, "Source unavailable.");
  assert.equal(record.completed, true);
  assert.equal(record.usage.totalTokens, 7);
  assert.equal(record.trace.at(-1).stopReason, "stop");
});
