import assert from "node:assert/strict";
import { execFileSync, spawnSync } from "node:child_process";
import { describe, it } from "node:test";

const CLI = new URL("../bin/intent.mjs", import.meta.url).pathname;
const VALID_CODE_CHANGE = new URL("../fixtures/valid_code_change.intent", import.meta.url).pathname;
const VALID_RESEARCH = new URL("../fixtures/valid_research.intent", import.meta.url).pathname;
const INVALID_MISSING_VERIFICATION = new URL("../fixtures/invalid_missing_verification.intent", import.meta.url).pathname;
const INVALID_UNDECLARED_EFFECT = new URL("../fixtures/invalid_undeclared_effect.intent", import.meta.url).pathname;
const INVALID_FILE_WRITE_OUTSIDE_CAPABILITY = new URL("../fixtures/invalid_file_write_outside_capability.intent", import.meta.url).pathname;
const INVALID_SHELL_EXEC_OUTSIDE_CAPABILITY = new URL("../fixtures/invalid_shell_exec_outside_capability.intent", import.meta.url).pathname;
const INVALID_UNRESOLVED_TYPE = new URL("../fixtures/invalid_unresolved_type.intent", import.meta.url).pathname;
const INVALID_UNRESOLVED_STEP_INPUT = new URL("../fixtures/invalid_unresolved_step_input.intent", import.meta.url).pathname;
const INVALID_DUPLICATE_STEP_NAME = new URL("../fixtures/invalid_duplicate_step_name.intent", import.meta.url).pathname;

function runJson(args) {
  const output = execFileSync("node", [CLI, ...args], { encoding: "utf8" });
  return JSON.parse(output);
}

function run(args) {
  return spawnSync("node", [CLI, ...args], { encoding: "utf8" });
}

describe("intent static model CLI", () => {
  it("parses goals into an AST with source spans", () => {
    const ast = runJson(["parse", VALID_CODE_CHANGE]);

    assert.equal(ast.schema_version, "intent.ast.v0");
    assert.equal(ast.package.name, "fixtures.code_change");
    assert.equal(ast.goals.length, 1);
    assert.equal(ast.types.length, 3);
    assert.equal(ast.goals[0].name, "apply_code_change");
    assert.equal(ast.goals[0].steps.length, 3);
    assert.equal(ast.goals[0].span.file, VALID_CODE_CHANGE);
    assert.equal(ast.goals[0].span.start.line, 15);
  });

  it("accepts valid fixtures", () => {
    const codeChange = runJson(["check", VALID_CODE_CHANGE]);
    const research = runJson(["check", VALID_RESEARCH]);

    assert.equal(codeChange.ok, true);
    assert.deepEqual(codeChange.diagnostics, []);
    assert.equal(research.ok, true);
    assert.deepEqual(research.diagnostics, []);
  });

  it("rejects effectful goals without verification", () => {
    const result = run(["check", INVALID_MISSING_VERIFICATION]);
    const payload = JSON.parse(result.stdout);

    assert.equal(result.status, 1);
    assert.equal(payload.ok, false);
    assert.equal(payload.diagnostics[0].code, "INTENT_VERIFY_MISSING");
  });

  it("rejects effects without matching capabilities", () => {
    const result = run(["check", INVALID_UNDECLARED_EFFECT]);
    const payload = JSON.parse(result.stdout);

    assert.equal(result.status, 1);
    assert.equal(payload.ok, false);
    assert.equal(payload.diagnostics[0].code, "INTENT_EFFECT_UNDECLARED");
    assert.equal(payload.diagnostics[0].effect, "GitPush");
  });

  it("rejects file writes outside declared path grants", () => {
    const result = run(["check", INVALID_FILE_WRITE_OUTSIDE_CAPABILITY]);
    const payload = JSON.parse(result.stdout);

    assert.equal(result.status, 1);
    assert.equal(payload.ok, false);
    assert.equal(payload.diagnostics[0].code, "INTENT_CAPABILITY_DENIED");
    assert.equal(payload.diagnostics[0].argument, "path");
    assert.equal(payload.diagnostics[0].value, "./README.md");
  });

  it("rejects shell commands outside declared command grants", () => {
    const result = run(["check", INVALID_SHELL_EXEC_OUTSIDE_CAPABILITY]);
    const payload = JSON.parse(result.stdout);

    assert.equal(result.status, 1);
    assert.equal(payload.ok, false);
    assert.equal(payload.diagnostics[0].code, "INTENT_CAPABILITY_DENIED");
    assert.equal(payload.diagnostics[0].argument, "command");
    assert.equal(payload.diagnostics[0].value, "npm run lint");
  });

  it("rejects unresolved type references", () => {
    const result = run(["check", INVALID_UNRESOLVED_TYPE]);
    const payload = JSON.parse(result.stdout);

    assert.equal(result.status, 1);
    assert.equal(payload.ok, false);
    assert.equal(payload.diagnostics[0].code, "INTENT_TYPE_UNRESOLVED");
    assert.equal(payload.diagnostics[0].type, "MissingType");
  });

  it("rejects duplicate step names", () => {
    const result = run(["check", INVALID_DUPLICATE_STEP_NAME]);
    const payload = JSON.parse(result.stdout);

    assert.equal(result.status, 1);
    assert.equal(payload.ok, false);
    assert.equal(payload.diagnostics[0].code, "INTENT_NAME_DUPLICATE");
    assert.equal(payload.diagnostics[0].name, "inspect_request");
  });

  it("rejects step inputs that are not produced yet", () => {
    const result = run(["check", INVALID_UNRESOLVED_STEP_INPUT]);
    const payload = JSON.parse(result.stdout);

    assert.equal(result.status, 1);
    assert.equal(payload.ok, false);
    assert.equal(payload.diagnostics[0].code, "INTENT_STEP_INPUT_UNRESOLVED");
    assert.equal(payload.diagnostics[0].type, "Finding");
  });

  it("emits an execution graph with goal, capability, step, and check nodes", () => {
    const graph = runJson(["graph", VALID_CODE_CHANGE]);
    const kinds = new Set(graph.nodes.map((node) => node.kind));

    assert.equal(graph.schema_version, "intent.graph.v0");
    assert.equal(graph.ok, true);
    assert.equal(kinds.has("Goal"), true);
    assert.equal(kinds.has("Type"), true);
    assert.equal(kinds.has("Capability"), true);
    assert.equal(kinds.has("Effect"), true);
    assert.equal(kinds.has("Step"), true);
    assert.equal(kinds.has("Check"), true);
    assert.equal(graph.nodes.some((node) => node.kind === "Effect" && node.data.args.path === "./src/app.ts"), true);
    assert.equal(graph.nodes.some((node) => node.kind === "Capability" && node.data.grants.some((grant) => grant.value === "npm test")), true);
    assert.equal(graph.edges.some((edge) => edge.kind === "plans"), true);
    assert.equal(graph.edges.some((edge) => edge.kind === "gates"), true);
  });
});
