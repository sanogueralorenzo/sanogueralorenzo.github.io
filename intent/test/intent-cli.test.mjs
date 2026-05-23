import assert from "node:assert/strict";
import { execFileSync, spawnSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { describe, it } from "node:test";

const CLI = new URL("../bin/intent.mjs", import.meta.url).pathname;
const AST_SCHEMA = new URL("../schemas/intent.ast.v0.schema.json", import.meta.url).pathname;
const CHECK_SCHEMA = new URL("../schemas/intent.check.v0.schema.json", import.meta.url).pathname;
const GRAPH_SCHEMA = new URL("../schemas/intent.graph.v0.schema.json", import.meta.url).pathname;
const VALID_CODE_CHANGE = new URL("../fixtures/valid_code_change.intent", import.meta.url).pathname;
const VALID_CHECKPOINT_GRAPH = new URL("../fixtures/valid_checkpoint_graph.intent", import.meta.url).pathname;
const VALID_CONTEXT_TRUST_GRAPH = new URL("../fixtures/valid_context_trust_graph.intent", import.meta.url).pathname;
const VALID_DEPENDENCY_GRAPH = new URL("../fixtures/valid_dependency_graph.intent", import.meta.url).pathname;
const VALID_RESEARCH = new URL("../fixtures/valid_research.intent", import.meta.url).pathname;
const VALID_WEB_READ_WILDCARD = new URL("../fixtures/valid_web_read_wildcard.intent", import.meta.url).pathname;
const VALID_GIT_PUSH_BRANCH = new URL("../fixtures/valid_git_push_branch.intent", import.meta.url).pathname;
const VALID_STEP_REQUIREMENTS = new URL("../fixtures/valid_step_requirements.intent", import.meta.url).pathname;
const VALID_INVARIANT_GUARD_GRAPH = new URL("../fixtures/valid_invariant_guard_graph.intent", import.meta.url).pathname;
const VALID_STEP_APPROVAL_GRAPH = new URL("../fixtures/valid_step_approval_graph.intent", import.meta.url).pathname;
const VALID_STEP_POLICY_GRAPH = new URL("../fixtures/valid_step_policy_graph.intent", import.meta.url).pathname;
const INVALID_MISSING_VERIFICATION = new URL("../fixtures/invalid_missing_verification.intent", import.meta.url).pathname;
const INVALID_UNDECLARED_EFFECT = new URL("../fixtures/invalid_undeclared_effect.intent", import.meta.url).pathname;
const INVALID_GIT_PUSH_BRANCH_MISMATCH = new URL("../fixtures/invalid_git_push_branch_mismatch.intent", import.meta.url).pathname;
const INVALID_FILE_WRITE_OUTSIDE_CAPABILITY = new URL("../fixtures/invalid_file_write_outside_capability.intent", import.meta.url).pathname;
const INVALID_SHELL_EXEC_OUTSIDE_CAPABILITY = new URL("../fixtures/invalid_shell_exec_outside_capability.intent", import.meta.url).pathname;
const INVALID_WEB_READ_OUTSIDE_CAPABILITY = new URL("../fixtures/invalid_web_read_outside_capability.intent", import.meta.url).pathname;
const INVALID_TRUST_FLOW_UNTRUSTED_SHELL_INPUT = new URL("../fixtures/invalid_trust_flow_untrusted_shell_input.intent", import.meta.url).pathname;
const INVALID_VERIFY_SHELL_WITHOUT_CAPABILITY = new URL("../fixtures/invalid_verify_shell_without_capability.intent", import.meta.url).pathname;
const INVALID_VERIFY_IMPURE_FILE_WRITE = new URL("../fixtures/invalid_verify_impure_file_write.intent", import.meta.url).pathname;
const INVALID_MEMORY_WITHOUT_RETENTION = new URL("../fixtures/invalid_memory_without_retention.intent", import.meta.url).pathname;
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

function readJson(file) {
  return JSON.parse(readFileSync(file, "utf8"));
}

function validateSchema(schema, value) {
  const errors = [];
  validateAgainst(schema, value, schema, "$", errors);
  return errors;
}

function validateAgainst(schema, value, root, path, errors) {
  if (schema.$ref) {
    validateAgainst(resolveRef(root, schema.$ref), value, root, path, errors);
    return;
  }
  if (schema.allOf) {
    for (const item of schema.allOf) {
      validateAgainst(item, value, root, path, errors);
    }
  }
  if (schema.oneOf) {
    const matches = schema.oneOf.filter((item) => validateSubschema(item, value, root));
    if (matches.length !== 1) {
      errors.push(`${path} must match exactly one schema, matched ${matches.length}`);
    }
    return;
  }
  if (schema.const !== undefined && value !== schema.const) {
    errors.push(`${path} must equal ${JSON.stringify(schema.const)}`);
  }
  if (schema.enum && !schema.enum.includes(value)) {
    errors.push(`${path} must be one of ${schema.enum.join(", ")}`);
  }
  if (schema.type && !matchesType(schema.type, value)) {
    errors.push(`${path} must be ${JSON.stringify(schema.type)}`);
    return;
  }
  if (typeof value === "number" && schema.minimum !== undefined && value < schema.minimum) {
    errors.push(`${path} must be >= ${schema.minimum}`);
  }
  if (schema.required && isPlainObject(value)) {
    for (const key of schema.required) {
      if (!(key in value)) {
        errors.push(`${path}.${key} is required`);
      }
    }
  }
  if (schema.properties && isPlainObject(value)) {
    for (const [key, propertySchema] of Object.entries(schema.properties)) {
      if (key in value) {
        validateAgainst(propertySchema, value[key], root, `${path}.${key}`, errors);
      }
    }
  }
  if (schema.additionalProperties === false && isPlainObject(value)) {
    const allowed = new Set(Object.keys(schema.properties ?? {}));
    for (const key of Object.keys(value)) {
      if (!allowed.has(key)) {
        errors.push(`${path}.${key} is not allowed`);
      }
    }
  } else if (isPlainObject(schema.additionalProperties) && isPlainObject(value)) {
    const known = new Set(Object.keys(schema.properties ?? {}));
    for (const key of Object.keys(value)) {
      if (!known.has(key)) {
        validateAgainst(schema.additionalProperties, value[key], root, `${path}.${key}`, errors);
      }
    }
  }
  if (schema.items && Array.isArray(value)) {
    value.forEach((item, index) => validateAgainst(schema.items, item, root, `${path}[${index}]`, errors));
  }
}

function validateSubschema(schema, value, root) {
  const errors = [];
  validateAgainst(schema, value, root, "$", errors);
  return errors.length === 0;
}

function resolveRef(root, ref) {
  assert.equal(ref.startsWith("#/"), true, `unsupported ref ${ref}`);
  return ref.slice(2).split("/").reduce((node, part) => node[part], root);
}

function matchesType(type, value) {
  const types = Array.isArray(type) ? type : [type];
  return types.some((candidate) => {
    if (candidate === "array") return Array.isArray(value);
    if (candidate === "object") return isPlainObject(value);
    if (candidate === "integer") return Number.isInteger(value);
    if (candidate === "null") return value === null;
    return typeof value === candidate;
  });
}

function isPlainObject(value) {
  return typeof value === "object" && value !== null && !Array.isArray(value);
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
    assert.equal(ast.goals[0].memory[0].retention[0], "retain summaries until goal_complete");
    assert.equal(ast.goals[0].memory[0].retentionRules[0].subject.raw, "summaries");
    assert.equal(ast.goals[0].memory[0].retentionRules[0].until.raw, "goal_complete");
    assert.equal(ast.goals[0].context[0].source, "repo");
    assert.equal(ast.goals[0].context[0].args._0, "./");
    assert.equal(ast.goals[0].context[0].trust.zone, "trusted");
    assert.equal(ast.goals[0].span.file, VALID_CODE_CHANGE);
    assert.equal(ast.goals[0].span.start.line, 15);
  });

  it("accepts valid fixtures", () => {
    const codeChange = runJson(["check", VALID_CODE_CHANGE]);
    const checkpointGraph = runJson(["check", VALID_CHECKPOINT_GRAPH]);
    const contextTrustGraph = runJson(["check", VALID_CONTEXT_TRUST_GRAPH]);
    const dependencyGraph = runJson(["check", VALID_DEPENDENCY_GRAPH]);
    const research = runJson(["check", VALID_RESEARCH]);
    const webReadWildcard = runJson(["check", VALID_WEB_READ_WILDCARD]);
    const gitPushBranch = runJson(["check", VALID_GIT_PUSH_BRANCH]);
    const stepRequirements = runJson(["check", VALID_STEP_REQUIREMENTS]);
    const invariantGuardGraph = runJson(["check", VALID_INVARIANT_GUARD_GRAPH]);
    const stepApprovalGraph = runJson(["check", VALID_STEP_APPROVAL_GRAPH]);
    const stepPolicyGraph = runJson(["check", VALID_STEP_POLICY_GRAPH]);
    const trustFlow = runJson(["check", new URL("../fixtures/valid_trust_flow_shell_literal.intent", import.meta.url).pathname]);

    assert.equal(codeChange.ok, true);
    assert.deepEqual(codeChange.diagnostics, []);
    assert.equal(checkpointGraph.ok, true);
    assert.deepEqual(checkpointGraph.diagnostics, []);
    assert.equal(contextTrustGraph.ok, true);
    assert.deepEqual(contextTrustGraph.diagnostics, []);
    assert.equal(dependencyGraph.ok, true);
    assert.deepEqual(dependencyGraph.diagnostics, []);
    assert.equal(research.ok, true);
    assert.deepEqual(research.diagnostics, []);
    assert.equal(webReadWildcard.ok, true);
    assert.deepEqual(webReadWildcard.diagnostics, []);
    assert.equal(gitPushBranch.ok, true);
    assert.deepEqual(gitPushBranch.diagnostics, []);
    assert.equal(stepRequirements.ok, true);
    assert.deepEqual(stepRequirements.diagnostics, []);
    assert.equal(invariantGuardGraph.ok, true);
    assert.deepEqual(invariantGuardGraph.diagnostics, []);
    assert.equal(stepApprovalGraph.ok, true);
    assert.deepEqual(stepApprovalGraph.diagnostics, []);
    assert.equal(stepPolicyGraph.ok, true);
    assert.deepEqual(stepPolicyGraph.diagnostics, []);
    assert.equal(trustFlow.ok, true);
    assert.deepEqual(trustFlow.diagnostics, []);
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

  it("rejects web reads outside declared domain grants", () => {
    const result = run(["check", INVALID_WEB_READ_OUTSIDE_CAPABILITY]);
    const payload = JSON.parse(result.stdout);

    assert.equal(result.status, 1);
    assert.equal(payload.ok, false);
    assert.equal(payload.diagnostics[0].code, "INTENT_CAPABILITY_DENIED");
    assert.equal(payload.diagnostics[0].argument, "domain");
    assert.equal(payload.diagnostics[0].value, "example.org");
    assert.deepEqual(payload.diagnostics[0].allowed, ["example.com"]);
  });

  it("rejects git pushes outside declared branch grants", () => {
    const result = run(["check", INVALID_GIT_PUSH_BRANCH_MISMATCH]);
    const payload = JSON.parse(result.stdout);

    assert.equal(result.status, 1);
    assert.equal(payload.ok, false);
    assert.equal(payload.diagnostics[0].code, "INTENT_CAPABILITY_DENIED");
    assert.equal(payload.diagnostics[0].argument, "branch");
    assert.equal(payload.diagnostics[0].value, "release");
    assert.deepEqual(payload.diagnostics[0].allowed, ["main"]);
  });

  it("rejects nonliteral shell commands as unsafe trust flow", () => {
    const result = run(["check", INVALID_TRUST_FLOW_UNTRUSTED_SHELL_INPUT]);
    const payload = JSON.parse(result.stdout);

    assert.equal(result.status, 1);
    assert.equal(payload.ok, false);
    assert.equal(payload.diagnostics[0].code, "INTENT_TRUST_FLOW_UNSAFE");
    assert.equal(payload.diagnostics[0].argument, "command");
    assert.equal(payload.diagnostics[0].trust, "untrusted");
    assert.equal(payload.diagnostics.length, 1);
  });

  it("rejects verification shell commands without matching capability grants", () => {
    const result = run(["check", INVALID_VERIFY_SHELL_WITHOUT_CAPABILITY]);
    const payload = JSON.parse(result.stdout);

    assert.equal(result.status, 1);
    assert.equal(payload.ok, false);
    assert.equal(payload.diagnostics[0].code, "INTENT_VERIFY_UNDECLARED");
    assert.equal(payload.diagnostics[0].requirement, "shell(\"npm run lint\").exit_code == 0");
    assert.equal(payload.diagnostics[0].argument, "command");
    assert.equal(payload.diagnostics[0].value, "npm run lint");
    assert.deepEqual(payload.diagnostics[0].allowed, ["npm test"]);
  });

  it("rejects side-effect calls inside verification requirements", () => {
    const result = run(["check", INVALID_VERIFY_IMPURE_FILE_WRITE]);
    const payload = JSON.parse(result.stdout);

    assert.equal(result.status, 1);
    assert.equal(payload.ok, false);
    assert.equal(payload.diagnostics[0].code, "INTENT_VERIFY_IMPURE");
    assert.equal(payload.diagnostics[0].requirement, "FileWrite(path: \"./src/app.ts\")");
    assert.equal(payload.diagnostics[0].effect, "FileWrite");
    assert.equal(payload.diagnostics[0].family, "file");
    assert.equal(payload.diagnostics[0].action, "write");
  });

  it("rejects memory blocks without retention lifecycle rules", () => {
    const result = run(["check", INVALID_MEMORY_WITHOUT_RETENTION]);
    const payload = JSON.parse(result.stdout);

    assert.equal(result.status, 1);
    assert.equal(payload.ok, false);
    assert.equal(payload.diagnostics[0].code, "INTENT_MEMORY_UNSCOPED");
    assert.equal(payload.diagnostics[0].memory, "project");
    assert.equal(payload.diagnostics[0].scope, "project");
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
    assert.equal(graph.nodes.some((node) => node.kind === "Effect" && node.data.trust.zone === "trusted"), true);
    assert.equal(graph.nodes.some((node) => node.kind === "Memory" && node.data.retentionRules[0].subject.raw === "summaries"), true);
    assert.equal(graph.nodes.some((node) => node.kind === "Check" && node.data.effect?.args.command === "npm test"), true);
    assert.equal(graph.nodes.some((node) => node.kind === "Capability" && node.data.grants.some((grant) => grant.value === "npm test")), true);
    assert.equal(graph.edges.some((edge) => edge.kind === "plans"), true);
    assert.equal(graph.edges.some((edge) => edge.kind === "gates"), true);
    assert.equal(graph.edges.some((edge) => edge.kind === "authorizes" && edge.to.includes(":verify:")), true);
  });

  it("emits structured context sources with first-prototype trust metadata", () => {
    const graph = runJson(["graph", VALID_CONTEXT_TRUST_GRAPH]);
    const repoContext = graph.nodes.find((node) => node.kind === "Context" && node.data.source === "repo");
    const webContext = graph.nodes.find((node) => node.kind === "Context" && node.data.source === "web");
    const documentsContext = graph.nodes.find((node) => node.kind === "Context" && node.data.source === "documents");

    assert.equal(graph.ok, true);
    assert.equal(repoContext.data.args._0, "./");
    assert.equal(repoContext.data.argKinds._0, "string");
    assert.equal(repoContext.data.expression, "repo(\"./\")");
    assert.equal(repoContext.data.trust.zone, "trusted");
    assert.equal(repoContext.data.trust.source, "local_context");
    assert.equal(webContext.data.args._0, "https://example.com/**");
    assert.equal(webContext.data.trust.zone, "untrusted");
    assert.equal(webContext.data.trust.source, "external_context");
    assert.equal(documentsContext.data.trust.zone, "trusted");
    assert.equal(graph.edges.some((edge) => edge.kind === "informs" && edge.from === webContext.id), true);
  });

  it("emits explicit data dependencies and completion gates", () => {
    const graph = runJson(["graph", VALID_DEPENDENCY_GRAPH]);
    const kinds = new Set(graph.nodes.map((node) => node.kind));

    assert.equal(graph.ok, true);
    assert.equal(kinds.has("Input"), true);
    assert.equal(kinds.has("Completion"), true);
    assert.equal(graph.edges.some((edge) => edge.kind === "data" && edge.data.type === "GoalRequest"), true);
    assert.equal(graph.edges.some((edge) => edge.kind === "data" && edge.data.type === "Finding"), true);
    assert.equal(graph.edges.some((edge) => edge.kind === "data" && edge.data.type === "Patch"), true);
    assert.equal(graph.edges.some((edge) => edge.kind === "verifies" && edge.to.endsWith(":completion")), true);
    assert.equal(graph.edges.some((edge) => edge.kind === "guards" && edge.to.endsWith(":completion")), true);
    assert.equal(graph.edges.some((edge) => edge.kind === "produces" && edge.to.endsWith(":completion")), true);
  });

  it("emits step requirement checks as preconditions without completion verification edges", () => {
    const graph = runJson(["graph", VALID_STEP_REQUIREMENTS]);
    const stepRequirement = graph.nodes.find((node) => node.kind === "Check" && node.data.scope === "step");

    assert.equal(graph.ok, true);
    assert.equal(stepRequirement.data.ownerStep, "patch_code");
    assert.equal(stepRequirement.data.requirement, "input.summary != \"\"");
    assert.equal(graph.edges.some((edge) => edge.from === stepRequirement.id && edge.kind === "requires" && edge.to.endsWith(":step:patch_code")), true);
    assert.equal(graph.edges.some((edge) => edge.from === stepRequirement.id && edge.kind === "gates" && edge.to === "goal:apply_guarded_code_change"), true);
    assert.equal(graph.edges.some((edge) => edge.from === stepRequirement.id && edge.kind === "verifies"), false);
  });

  it("emits step checkpoints as checkpoint nodes and edges", () => {
    const graph = runJson(["graph", VALID_CHECKPOINT_GRAPH]);
    const checkpoint = graph.nodes.find((node) => node.kind === "Checkpoint" && node.data.ownerStep === "patch_code");
    const patchStep = graph.nodes.find((node) => node.kind === "Step" && node.label === "patch_code");

    assert.equal(graph.ok, true);
    assert.equal(checkpoint.data.scope, "step");
    assert.equal(checkpoint.data.checkpoint, "before patch");
    assert.equal(patchStep.data.checkpoints.includes("before patch"), true);
    assert.equal(graph.edges.some((edge) => edge.kind === "checkpoints" && edge.from === patchStep.id && edge.to === checkpoint.id), true);
    assert.equal(graph.edges.some((edge) => edge.from === checkpoint.id && edge.kind === "verifies"), false);
  });

  it("emits invariant guards to completion, effects, checkpoints, and step requirements", () => {
    const graph = runJson(["graph", VALID_INVARIANT_GUARD_GRAPH]);
    const invariant = graph.nodes.find((node) => node.kind === "Invariant" && node.data.invariant === "secret_write");
    const effect = graph.nodes.find((node) => node.kind === "Effect" && node.data.family === "file");
    const checkpoint = graph.nodes.find((node) => node.kind === "Checkpoint" && node.data.ownerStep === "patch_code");
    const requirement = graph.nodes.find((node) => node.kind === "Check" && node.data.scope === "step");

    assert.equal(graph.ok, true);
    assert.equal(graph.edges.some((edge) => edge.kind === "guards" && edge.from === invariant.id && edge.to.endsWith(":completion")), true);
    assert.equal(graph.edges.some((edge) => edge.kind === "guards" && edge.from === invariant.id && edge.to === effect.id), true);
    assert.equal(graph.edges.some((edge) => edge.kind === "guards" && edge.from === invariant.id && edge.to === checkpoint.id), true);
    assert.equal(graph.edges.some((edge) => edge.kind === "guards" && edge.from === invariant.id && edge.to === requirement.id), true);
  });

  it("emits step approvals as approval nodes and edges", () => {
    const graph = runJson(["graph", VALID_STEP_APPROVAL_GRAPH]);
    const approval = graph.nodes.find((node) => node.kind === "Approval" && node.data.ownerStep === "publish_patch");
    const publishStep = graph.nodes.find((node) => node.kind === "Step" && node.label === "publish_patch");

    assert.equal(graph.ok, true);
    assert.equal(approval.data.scope, "step");
    assert.equal(approval.data.approval, "maintainer approves main push");
    assert.equal(publishStep.data.approvals.includes("maintainer approves main push"), true);
    assert.equal(graph.edges.some((edge) => edge.kind === "approves" && edge.from === approval.id && edge.to === publishStep.id), true);
    assert.equal(graph.edges.some((edge) => edge.from === approval.id && edge.kind === "verifies"), false);
  });

  it("emits step timeout and retry policies as policy nodes and edges", () => {
    const graph = runJson(["graph", VALID_STEP_POLICY_GRAPH]);
    const patchStep = graph.nodes.find((node) => node.kind === "Step" && node.label === "patch_code");
    const timeout = graph.nodes.find((node) => node.kind === "Policy" && node.data.policyKind === "timeout");
    const retry = graph.nodes.find((node) => node.kind === "Policy" && node.data.policyKind === "retry");

    assert.equal(graph.ok, true);
    assert.equal(timeout.data.scope, "step");
    assert.equal(timeout.data.ownerStep, "patch_code");
    assert.equal(timeout.data.policy, "5m");
    assert.equal(retry.data.scope, "step");
    assert.equal(retry.data.ownerStep, "patch_code");
    assert.equal(retry.data.policy, "max 2");
    assert.equal(patchStep.data.timeouts.includes("5m"), true);
    assert.equal(patchStep.data.retries.includes("max 2"), true);
    assert.equal(graph.edges.some((edge) => edge.kind === "timeouts" && edge.from === timeout.id && edge.to === patchStep.id), true);
    assert.equal(graph.edges.some((edge) => edge.kind === "retries" && edge.from === retry.id && edge.to === patchStep.id), true);
    assert.equal(graph.edges.some((edge) => edge.from === timeout.id && edge.kind === "verifies"), false);
  });

  it("validates CLI outputs against versioned schemas", () => {
    const astSchema = readJson(AST_SCHEMA);
    const checkSchema = readJson(CHECK_SCHEMA);
    const graphSchema = readJson(GRAPH_SCHEMA);
    const ast = runJson(["parse", VALID_DEPENDENCY_GRAPH]);
    const validCheck = runJson(["check", VALID_DEPENDENCY_GRAPH]);
    const invalidCheck = JSON.parse(run(["check", INVALID_UNRESOLVED_TYPE]).stdout);
    const graph = runJson(["graph", VALID_DEPENDENCY_GRAPH]);
    const policyGraph = runJson(["graph", VALID_STEP_POLICY_GRAPH]);
    const contextGraph = runJson(["graph", VALID_CONTEXT_TRUST_GRAPH]);

    assert.deepEqual(validateSchema(astSchema, ast), []);
    assert.deepEqual(validateSchema(checkSchema, validCheck), []);
    assert.deepEqual(validateSchema(checkSchema, invalidCheck), []);
    assert.deepEqual(validateSchema(graphSchema, graph), []);
    assert.deepEqual(validateSchema(graphSchema, policyGraph), []);
    assert.deepEqual(validateSchema(graphSchema, contextGraph), []);
  });
});
