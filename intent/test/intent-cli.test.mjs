import assert from "node:assert/strict";
import { execFileSync, spawnSync } from "node:child_process";
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { describe, it } from "node:test";
import { validateGraph } from "../bin/intent.mjs";

const CLI = new URL("../bin/intent.mjs", import.meta.url).pathname;
const STATIC_MODEL = new URL("../STATIC_MODEL.md", import.meta.url).pathname;
const AST_SCHEMA = new URL("../schemas/intent.ast.v0.schema.json", import.meta.url).pathname;
const CHECK_SCHEMA = new URL("../schemas/intent.check.v0.schema.json", import.meta.url).pathname;
const GRAPH_SCHEMA = new URL("../schemas/intent.graph.v0.schema.json", import.meta.url).pathname;
const EFFECT_CONTRACT_SCHEMA = new URL("../schemas/intent.effect-contracts.v0.schema.json", import.meta.url).pathname;
const VALID_CODE_CHANGE = new URL("../fixtures/valid_code_change.intent", import.meta.url).pathname;
const VALID_CHECKPOINT_GRAPH = new URL("../fixtures/valid_checkpoint_graph.intent", import.meta.url).pathname;
const VALID_CONTEXT_TRUST_GRAPH = new URL("../fixtures/valid_context_trust_graph.intent", import.meta.url).pathname;
const VALID_DEPLOY_TARGET = new URL("../fixtures/valid_deploy_target.intent", import.meta.url).pathname;
const VALID_DEPENDENCY_GRAPH = new URL("../fixtures/valid_dependency_graph.intent", import.meta.url).pathname;
const VALID_GIT_COMMIT_MESSAGE = new URL("../fixtures/valid_git_commit_message.intent", import.meta.url).pathname;
const VALID_RESEARCH = new URL("../fixtures/valid_research.intent", import.meta.url).pathname;
const VALID_SECRET_READ = new URL("../fixtures/valid_secret_read.intent", import.meta.url).pathname;
const VALID_TICKET_UPDATE = new URL("../fixtures/valid_ticket_update.intent", import.meta.url).pathname;
const VALID_WEB_READ_WILDCARD = new URL("../fixtures/valid_web_read_wildcard.intent", import.meta.url).pathname;
const VALID_GIT_PUSH_BRANCH = new URL("../fixtures/valid_git_push_branch.intent", import.meta.url).pathname;
const VALID_IRREVERSIBLE_CHECKPOINT_COVERAGE = new URL("../fixtures/valid_irreversible_checkpoint_coverage.intent", import.meta.url).pathname;
const VALID_STEP_REQUIREMENTS = new URL("../fixtures/valid_step_requirements.intent", import.meta.url).pathname;
const VALID_INVARIANT_GUARD_GRAPH = new URL("../fixtures/valid_invariant_guard_graph.intent", import.meta.url).pathname;
const VALID_IMPORTS = new URL("../fixtures/valid_imports.intent", import.meta.url).pathname;
const VALID_MEMORY_FLOW_GRAPH = new URL("../fixtures/valid_memory_flow_graph.intent", import.meta.url).pathname;
const VALID_STEP_APPROVAL_GRAPH = new URL("../fixtures/valid_step_approval_graph.intent", import.meta.url).pathname;
const VALID_STEP_POLICY_GRAPH = new URL("../fixtures/valid_step_policy_graph.intent", import.meta.url).pathname;
const VALID_TRUST_FLOW_SHELL_LITERAL = new URL("../fixtures/valid_trust_flow_shell_literal.intent", import.meta.url).pathname;
const EXAMPLE_CODE_CHANGE = new URL("../examples/code_change.intent", import.meta.url).pathname;
const EXAMPLE_RESEARCH_SYNTHESIS = new URL("../examples/research_synthesis.intent", import.meta.url).pathname;
const EXAMPLE_INCIDENT_RESPONSE = new URL("../examples/incident_response.intent", import.meta.url).pathname;
const EXAMPLE_DEPLOYMENT_APPROVAL = new URL("../examples/deployment_approval.intent", import.meta.url).pathname;
const INVALID_GOAL_MISSING = new URL("../fixtures/invalid_goal_missing.intent", import.meta.url).pathname;
const INVALID_MISSING_PACKAGE = new URL("../fixtures/invalid_missing_package.intent", import.meta.url).pathname;
const INVALID_DUPLICATE_PACKAGE = new URL("../fixtures/invalid_duplicate_package.intent", import.meta.url).pathname;
const INVALID_IMPORT_AFTER_TYPE = new URL("../fixtures/invalid_import_after_type.intent", import.meta.url).pathname;
const INVALID_EMPTY_TYPE_DEFINITION = new URL("../fixtures/invalid_empty_type_definition.intent", import.meta.url).pathname;
const INVALID_MISSING_VERIFICATION = new URL("../fixtures/invalid_missing_verification.intent", import.meta.url).pathname;
const INVALID_UNDECLARED_EFFECT = new URL("../fixtures/invalid_undeclared_effect.intent", import.meta.url).pathname;
const INVALID_UNKNOWN_EFFECT_CONTRACT = new URL("../fixtures/invalid_unknown_effect_contract.intent", import.meta.url).pathname;
const INVALID_EFFECT_ARGUMENT_TYPE = new URL("../fixtures/invalid_effect_argument_type.intent", import.meta.url).pathname;
const INVALID_GIT_PUSH_BRANCH_MISMATCH = new URL("../fixtures/invalid_git_push_branch_mismatch.intent", import.meta.url).pathname;
const INVALID_APPROVAL_REQUIRED_MISSING = new URL("../fixtures/invalid_approval_required_missing.intent", import.meta.url).pathname;
const INVALID_FILE_WRITE_OUTSIDE_CAPABILITY = new URL("../fixtures/invalid_file_write_outside_capability.intent", import.meta.url).pathname;
const INVALID_FILE_WRITE_ABSOLUTE_PATH = new URL("../fixtures/invalid_file_write_absolute_path.intent", import.meta.url).pathname;
const INVALID_SHELL_EXEC_OUTSIDE_CAPABILITY = new URL("../fixtures/invalid_shell_exec_outside_capability.intent", import.meta.url).pathname;
const INVALID_SECRET_READ_OUTSIDE_CAPABILITY = new URL("../fixtures/invalid_secret_read_outside_capability.intent", import.meta.url).pathname;
const INVALID_TICKET_UPDATE_OUTSIDE_CAPABILITY = new URL("../fixtures/invalid_ticket_update_outside_capability.intent", import.meta.url).pathname;
const INVALID_WEB_READ_OUTSIDE_CAPABILITY = new URL("../fixtures/invalid_web_read_outside_capability.intent", import.meta.url).pathname;
const INVALID_CONTEXT_SOURCE_OUTSIDE_CAPABILITY = new URL("../fixtures/invalid_context_source_outside_capability.intent", import.meta.url).pathname;
const INVALID_CONTEXT_ARGUMENT_TYPE = new URL("../fixtures/invalid_context_argument_type.intent", import.meta.url).pathname;
const INVALID_DEPLOY_TARGET_OUTSIDE_CAPABILITY = new URL("../fixtures/invalid_deploy_target_outside_capability.intent", import.meta.url).pathname;
const INVALID_INVARIANT_PRODUCTION_DEPLOY = new URL("../fixtures/invalid_invariant_production_deploy.intent", import.meta.url).pathname;
const INVALID_INVARIANT_SECRET_WRITE = new URL("../fixtures/invalid_invariant_secret_write.intent", import.meta.url).pathname;
const INVALID_INVARIANT_UNRELATED_FILE_WRITE = new URL("../fixtures/invalid_invariant_unrelated_file_write.intent", import.meta.url).pathname;
const INVALID_GIT_COMMIT_MESSAGE_MISMATCH = new URL("../fixtures/invalid_git_commit_message_mismatch.intent", import.meta.url).pathname;
const INVALID_TRUST_FLOW_UNTRUSTED_EFFECT_SINKS = new URL("../fixtures/invalid_trust_flow_untrusted_effect_sinks.intent", import.meta.url).pathname;
const INVALID_TRUST_FLOW_UNTRUSTED_SHELL_INPUT = new URL("../fixtures/invalid_trust_flow_untrusted_shell_input.intent", import.meta.url).pathname;
const INVALID_VERIFY_SHELL_WITHOUT_CAPABILITY = new URL("../fixtures/invalid_verify_shell_without_capability.intent", import.meta.url).pathname;
const INVALID_VERIFY_IMPURE_FILE_WRITE = new URL("../fixtures/invalid_verify_impure_file_write.intent", import.meta.url).pathname;
const INVALID_VERIFY_IMPURE_CUSTOM_EFFECT = new URL("../fixtures/invalid_verify_impure_custom_effect.intent", import.meta.url).pathname;
const INVALID_MEMORY_WITHOUT_RETENTION = new URL("../fixtures/invalid_memory_without_retention.intent", import.meta.url).pathname;
const INVALID_MEMORY_RETENTION_UNKNOWN_UNTIL = new URL("../fixtures/invalid_memory_retention_unknown_until.intent", import.meta.url).pathname;
const INVALID_MEMORY_ACCESS_UNDECLARED = new URL("../fixtures/invalid_memory_access_undeclared.intent", import.meta.url).pathname;
const INVALID_MEMORY_KEY_UNDECLARED = new URL("../fixtures/invalid_memory_key_undeclared.intent", import.meta.url).pathname;
const INVALID_PROVENANCE_MISSING = new URL("../fixtures/invalid_provenance_missing.intent", import.meta.url).pathname;
const INVALID_PROVENANCE_UNBACKED = new URL("../fixtures/invalid_provenance_unbacked.intent", import.meta.url).pathname;
const INVALID_COMPLETION_CHECKPOINT_MISSING = new URL("../fixtures/invalid_completion_checkpoint_missing.intent", import.meta.url).pathname;
const INVALID_UNCHECKPOINTED_IRREVERSIBLE_EFFECT = new URL("../fixtures/invalid_uncheckpointed_irreversible_effect.intent", import.meta.url).pathname;
const INVALID_IRREVERSIBLE_CHECKPOINT_BEFORE_EFFECT = new URL("../fixtures/invalid_irreversible_checkpoint_before_effect.intent", import.meta.url).pathname;
const INVALID_STEP_POLICY_BAD_TIMEOUT = new URL("../fixtures/invalid_step_policy_bad_timeout.intent", import.meta.url).pathname;
const INVALID_CHECKPOINT_EMPTY = new URL("../fixtures/invalid_checkpoint_empty.intent", import.meta.url).pathname;
const INVALID_APPROVAL_EMPTY = new URL("../fixtures/invalid_approval_empty.intent", import.meta.url).pathname;
const INVALID_UNRESOLVED_TYPE = new URL("../fixtures/invalid_unresolved_type.intent", import.meta.url).pathname;
const INVALID_UNRESOLVED_STEP_INPUT = new URL("../fixtures/invalid_unresolved_step_input.intent", import.meta.url).pathname;
const INVALID_GOAL_OUTPUT_TYPE_MISMATCH = new URL("../fixtures/invalid_goal_output_type_mismatch.intent", import.meta.url).pathname;
const INVALID_DUPLICATE_STEP_NAME = new URL("../fixtures/invalid_duplicate_step_name.intent", import.meta.url).pathname;
const INVALID_DUPLICATE_GOAL_NAME = new URL("../fixtures/invalid_duplicate_goal_name.intent", import.meta.url).pathname;
const INVALID_DUPLICATE_TYPE_NAME = new URL("../fixtures/invalid_duplicate_type_name.intent", import.meta.url).pathname;
const INVALID_DUPLICATE_GOAL_INPUT = new URL("../fixtures/invalid_duplicate_goal_input.intent", import.meta.url).pathname;
const INVALID_DUPLICATE_STEP_INPUT = new URL("../fixtures/invalid_duplicate_step_input.intent", import.meta.url).pathname;
const INVALID_UNSUPPORTED_GOAL_STATEMENT = new URL("../fixtures/invalid_unsupported_goal_statement.intent", import.meta.url).pathname;
const INVALID_UNSUPPORTED_PLAN_STATEMENT = new URL("../fixtures/invalid_unsupported_plan_statement.intent", import.meta.url).pathname;
const INVALID_UNSUPPORTED_STEP_STATEMENT = new URL("../fixtures/invalid_unsupported_step_statement.intent", import.meta.url).pathname;
const INVALID_UNSUPPORTED_VERIFY_STATEMENT = new URL("../fixtures/invalid_unsupported_verify_statement.intent", import.meta.url).pathname;
const INVALID_UNSUPPORTED_INVARIANT_STATEMENT = new URL("../fixtures/invalid_unsupported_invariant_statement.intent", import.meta.url).pathname;
const EXECUTABLE_EXAMPLES = [
  EXAMPLE_CODE_CHANGE,
  EXAMPLE_RESEARCH_SYNTHESIS,
  EXAMPLE_INCIDENT_RESPONSE,
  EXAMPLE_DEPLOYMENT_APPROVAL,
];

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

function emittedDiagnosticCodes() {
  const source = readFileSync(CLI, "utf8");
  const errorCallCodes = [...source.matchAll(/error\("([A-Z0-9_]+)"/g)].map((match) => match[1]);
  const literalCodes = [...source.matchAll(/code:\s*"([A-Z0-9_]+)"/g)].map((match) => match[1]);
  return [...new Set([...errorCallCodes, ...literalCodes])].sort();
}

function documentedDiagnosticCodes() {
  const source = readFileSync(STATIC_MODEL, "utf8");
  return [...new Set([...source.matchAll(/`(INTENT_[A-Z0-9_]+)`/g)].map((match) => match[1]))].sort();
}

function testSpan(line) {
  return {
    file: "synthetic.intent",
    start: { line, column: 1, offset: 0 },
    end: { line, column: 1, offset: 0 },
  };
}

function testSpanOffset(line, offset) {
  return {
    file: "synthetic.intent",
    start: { line, column: 1, offset },
    end: { line, column: 1, offset },
  };
}

function testGrant(action, key, value, line) {
  return {
    action,
    key,
    value,
    args: [{
      key,
      value,
      kind: "string",
      keySpan: testSpan(line),
      valueSpan: testSpan(line),
      span: testSpan(line),
    }],
    approvalRequired: false,
    raw: `${action} ${key}: "${value}"`,
    span: testSpan(line),
    actionSpan: testSpan(line),
  };
}

function testAuthorizationGrant(argument, sourceArgument, value, grantAction, grantKey, grantValue, line, grantApprovalRequired = false) {
  const grantArg = {
    key: grantKey,
    value: grantValue,
    kind: "string",
    keySpan: testSpan(line),
    valueSpan: testSpan(line),
    span: testSpan(line),
  };
  return {
    argument,
    sourceArgument,
    value,
    grantAction,
    grantKey,
    grantValue,
    grantApprovalRequired,
    grantSpan: testSpan(line),
    grantActionSpan: testSpan(line),
    grantArgumentSpan: testSpan(line),
    grantKeySpan: testSpan(line),
    grantValueSpan: testSpan(line),
    grantArgs: [grantArg],
  };
}

function validateTestGraph(graph) {
  const normalizedNodes = graph.nodes?.map((node, index) => {
    return isPlainObject(node)
      ? {
          label: node.id ?? `node:${index}`,
          span: testSpan(index + 1),
          ...node,
          data: defaultGraphNodeData(node.kind, node.data),
        }
      : node;
  });
  const nodesById = new Map((normalizedNodes ?? [])
    .filter((node) => isPlainObject(node) && typeof node.id === "string")
    .map((node) => [node.id, node]));
  const normalizedGraph = {
    ...graph,
    nodes: normalizedNodes,
    edges: graph.edges?.map((edge) => {
      return isPlainObject(edge)
        ? {
            ...edge,
            data: defaultGraphEdgeData(edge, edge.data, nodesById),
          }
        : edge;
    }),
  };
  return validateGraph({
    schema_version: "intent.graph.v0",
    ast_schema_version: "intent.ast.v0",
    source: "synthetic.intent",
    package: "fixtures.synthetic",
    ok: true,
    diagnostics: [],
    ...normalizedGraph,
  });
}

function spanSort(left, right) {
  return (left.span?.start?.offset ?? left.span?.start?.line ?? 0) - (right.span?.start?.offset ?? right.span?.start?.line ?? 0);
}

function attachedStepValues(graph, step, field) {
  const nodesById = new Map(graph.nodes.map((node) => [node.id, node]));
  const incoming = graph.edges.filter((edge) => edge.to === step.id);
  const outgoing = graph.edges.filter((edge) => edge.from === step.id);
  if (field === "inputs") {
    return incoming.filter((edge) => edge.kind === "requires" && nodesById.get(edge.from)?.kind === "Input" && nodesById.get(edge.from)?.data.scope === "step")
      .map((edge) => nodesById.get(edge.from)).sort(spanSort).map((node) => ({ name: node.label, type: node.data.type, span: node.span }));
  }
  if (field === "effects") {
    return outgoing.filter((edge) => edge.kind === "requests" && nodesById.get(edge.to)?.kind === "Effect")
      .map((edge) => nodesById.get(edge.to)).sort(spanSort).map((node) => node.label);
  }
  if (field === "requirements") {
    return incoming.filter((edge) => edge.kind === "requires" && nodesById.get(edge.from)?.kind === "Check" && nodesById.get(edge.from)?.data.scope === "step")
      .map((edge) => nodesById.get(edge.from)).sort(spanSort).map((node) => node.data.requirement);
  }
  if (field === "checkpoints") {
    return outgoing.filter((edge) => edge.kind === "checkpoints" && nodesById.get(edge.to)?.kind === "Checkpoint")
      .map((edge) => nodesById.get(edge.to)).sort(spanSort).map((node) => node.data.checkpoint);
  }
  if (field === "approvals") {
    return incoming.filter((edge) => edge.kind === "approves" && nodesById.get(edge.from)?.kind === "Approval")
      .map((edge) => nodesById.get(edge.from)).sort(spanSort).map((node) => node.data.approval);
  }
  if (field === "memoryAccesses") {
    return [
      ...incoming.filter((edge) => ["reads", "cites"].includes(edge.kind) && nodesById.get(edge.from)?.kind === "Memory"),
      ...outgoing.filter((edge) => edge.kind === "writes" && nodesById.get(edge.to)?.kind === "Memory"),
    ].sort((left, right) => {
      const leftSpan = left.kind === "writes" ? left.data.sourceSpan : left.data.targetSpan;
      const rightSpan = right.kind === "writes" ? right.data.sourceSpan : right.data.targetSpan;
      return (leftSpan?.start?.offset ?? leftSpan?.start?.line ?? 0) - (rightSpan?.start?.offset ?? rightSpan?.start?.line ?? 0);
    }).map((edge) => edge.data.target);
  }
  const policyKind = field === "timeouts" ? "timeout" : "retry";
  return incoming.filter((edge) => edge.kind === field && nodesById.get(edge.from)?.kind === "Policy" && nodesById.get(edge.from)?.data.policyKind === policyKind)
    .map((edge) => nodesById.get(edge.from)).sort(spanSort).map((node) => node.data.policy);
}

function attachedGoalValues(graph, goal, field) {
  const nodesById = new Map(graph.nodes.map((node) => [node.id, node]));
  if (field === "parameters") {
    return graph.edges
      .filter((edge) => edge.kind === "supplies" && edge.to === goal.id && nodesById.get(edge.from)?.kind === "Input" && nodesById.get(edge.from)?.data.scope === "goal")
      .map((edge) => nodesById.get(edge.from))
      .sort(spanSort)
      .map((node) => ({ name: node.label, type: node.data.type, span: node.span }));
  }
  const completion = nodesById.get(`${goal.id}:completion`);
  return {
    outputType: completion?.data.outputType,
    outputTypeSpan: completion?.data.outputTypeSpan,
  };
}

function defaultGraphNodeData(kind, data) {
  const normalizedData = isPlainObject(data) ? data : {};
  if (kind === "Type") {
    return { definition: null, ...normalizedData };
  }
  if (kind === "Context") {
    return {
      source: "repo",
      args: {},
      argKinds: {},
      argSpans: {},
      expression: "repo()",
      trust: { zone: "unknown", source: "synthetic" },
      ...normalizedData,
    };
  }
  if (kind === "Effect") {
    return {
      family: "file",
      action: "write",
      contractId: "intent.effect.file.write.v0",
      contractArguments: {},
      args: {},
      argKinds: {},
      argSpans: {},
      trust: { zone: "unknown", source: "synthetic" },
      expression: "FileWrite()",
      approvalRequired: false,
      ...normalizedData,
    };
  }
  if (kind === "Capability") {
    return { family: "synthetic", action: null, grants: [], approvalPolicy: "none", ...normalizedData };
  }
  if (kind === "Goal") {
    return { title: null, parameters: [], outputType: "Synthetic", outputTypeSpan: testSpan(1), ...normalizedData };
  }
  if (kind === "Completion") {
    return {
      outputType: "Synthetic",
      outputTypeSpan: testSpan(1),
      provenance: { required: false, requirements: [], invariants: [], citations: [] },
      checkpoint: { required: false, requirements: [], invariants: [], checkpoints: [] },
      ...normalizedData,
    };
  }
  if (kind === "Invariant") {
    return { assertion: "Deny", invariant: "synthetic", ...normalizedData };
  }
  if (kind === "Memory") {
    return {
      scope: "session",
      retention: ["retain evidence until goal_complete"],
      retentionRules: [{ raw: "retain evidence until goal_complete", subject: { raw: "evidence" }, until: { raw: "goal_complete" } }],
      keys: [],
      ...normalizedData,
    };
  }
  if (kind === "Input") {
    return { scope: "goal", type: "Synthetic", ...normalizedData };
  }
  if (kind === "Step") {
    return {
      inputs: [],
      outputType: "Synthetic",
      outputTypeSpan: testSpan(1),
      effects: [],
      requirements: [],
      checkpoints: [],
      approvals: [],
      timeouts: [],
      retries: [],
      memoryAccesses: [],
      ...normalizedData,
    };
  }
  if (kind === "Policy") {
    return { scope: "step", ownerStep: "patch", policyKind: "timeout", policy: "5m", ...normalizedData };
  }
  if (kind === "Approval") {
    return { scope: "step", ownerStep: "patch", approval: "maintainer", ...normalizedData };
  }
  if (kind === "Checkpoint") {
    return { scope: "step", ownerStep: "patch", checkpoint: "before patch", ...normalizedData };
  }
  if (kind === "Check") {
    const baseData = { requirement: "synthetic", ...normalizedData };
    if (baseData.scope === "step") {
      baseData.ownerStep ??= "patch";
      baseData.assertion ??= "Require";
    }
    if (isPlainObject(baseData.effect)) {
      baseData.effect = {
        family: "shell",
        action: "run",
        contractId: "intent.effect.shell.run.v0",
        contractArguments: {},
        args: {},
        argKinds: {},
        argSpans: {},
        trust: { zone: "unknown", source: "synthetic" },
        ...baseData.effect,
      };
    }
    return baseData;
  }
  return normalizedData;
}

function defaultGraphEdgeData(edge, data, nodesById = new Map()) {
  if (data !== undefined) {
    return data;
  }
  if (edge.kind === "gates" || edge.kind === "verifies") {
    const sourceNode = nodesById.get(edge.from);
    const targetNode = nodesById.get(edge.to);
    return {
      requirement: sourceNode?.data?.requirement ?? "synthetic",
      scope: sourceNode?.data?.scope === "step" ? "step" : "goal",
      sourceSpan: sourceNode?.span ?? testSpan(1),
      targetSpan: targetNode?.span ?? testSpan(1),
    };
  }
  if (edge.kind === "produces") {
    return { type: "Synthetic", sourceSpan: testSpan(1), targetSpan: testSpan(1) };
  }
  if (edge.kind === "requests") {
    const sourceNode = nodesById.get(edge.from);
    const targetNode = nodesById.get(edge.to);
    if (sourceNode?.kind === "Step" && targetNode?.kind === "Effect") {
      return {
        name: targetNode.label,
        expression: targetNode.data.expression,
        family: targetNode.data.family,
        action: targetNode.data.action,
        contractId: targetNode.data.contractId ?? null,
        contractArguments: targetNode.data.contractArguments ?? {},
        args: targetNode.data.args ?? {},
        argKinds: targetNode.data.argKinds ?? {},
        argSpans: targetNode.data.argSpans ?? {},
        sourceSpan: sourceNode.span,
        targetSpan: targetNode.span,
      };
    }
  }
  if (edge.kind === "informs") {
    const sourceNode = nodesById.get(edge.from);
    const targetNode = nodesById.get(edge.to);
    if (sourceNode?.kind === "Context" && targetNode?.kind === "Goal") {
      return {
        source: sourceNode.data.source,
        expression: sourceNode.data.expression,
        args: sourceNode.data.args ?? {},
        argKinds: sourceNode.data.argKinds ?? {},
        argSpans: sourceNode.data.argSpans ?? {},
        trust: sourceNode.data.trust,
        contractId: sourceNode.data.contractId ?? null,
        contractArguments: sourceNode.data.contractArguments ?? {},
        sourceSpan: sourceNode.span,
        targetSpan: targetNode.span,
      };
    }
  }
  if (edge.kind === "plans") {
    const sourceNode = nodesById.get(edge.from);
    const targetNode = nodesById.get(edge.to);
    if (sourceNode?.kind === "Goal" && targetNode?.kind === "Step") {
      const steps = [...nodesById.values()].filter((node) => node.kind === "Step" && node.id.startsWith(`${sourceNode.id}:step:`));
      return {
        goal: sourceNode.label,
        step: targetNode.label,
        index: steps.findIndex((node) => node.id === targetNode.id),
        sourceSpan: sourceNode.span,
        targetSpan: targetNode.span,
      };
    }
  }
  if (edge.kind === "precedes") {
    const sourceNode = nodesById.get(edge.from);
    const targetNode = nodesById.get(edge.to);
    const goalId = typeof sourceNode?.id === "string" ? sourceNode.id.split(":step:")[0] : null;
    if (sourceNode?.kind === "Step" && targetNode?.kind === "Step" && goalId) {
      const steps = [...nodesById.values()].filter((node) => node.kind === "Step" && node.id.startsWith(`${goalId}:step:`));
      return {
        previousStep: sourceNode.label,
        nextStep: targetNode.label,
        previousIndex: steps.findIndex((node) => node.id === sourceNode.id),
        nextIndex: steps.findIndex((node) => node.id === targetNode.id),
        sourceSpan: sourceNode.span,
        targetSpan: targetNode.span,
      };
    }
  }
  if (edge.kind === "declares") {
    const sourceNode = nodesById.get(edge.from);
    const targetNode = nodesById.get(edge.to);
    if (sourceNode?.kind === "Type" && targetNode?.kind === "Goal") {
      return {
        type: sourceNode.label,
        definition: sourceNode.data?.definition ?? null,
        goal: targetNode.label,
        sourceSpan: sourceNode.span,
        targetSpan: targetNode.span,
      };
    }
    if (sourceNode?.kind === "Goal" && targetNode?.kind === "Memory") {
      return {
        goal: sourceNode.label,
        memory: targetNode.label,
        memoryScope: targetNode.data?.scope ?? "session",
        sourceSpan: sourceNode.span,
        targetSpan: targetNode.span,
      };
    }
  }
  if (edge.kind === "authorizes") {
    const sourceNode = nodesById.get(edge.from);
    const targetNode = nodesById.get(edge.to);
    if (sourceNode?.kind === "Capability" && targetNode?.kind === "Goal") {
      return {
        capability: sourceNode.label,
        family: sourceNode.data?.family ?? "synthetic",
        approvalPolicy: sourceNode.data?.approvalPolicy ?? "none",
        goal: targetNode.label,
        sourceSpan: sourceNode.span,
        targetSpan: targetNode.span,
        ...(sourceNode.data?.action ? { action: sourceNode.data.action } : {}),
      };
    }
  }
  if (edge.kind === "requires" && typeof edge.from === "string" && edge.from.includes(":requirement:")) {
    return { requirement: "synthetic" };
  }
  if (edge.kind === "requires") {
    return { parameter: "input", type: "Synthetic", targetSpan: testSpan(1) };
  }
  if (edge.kind === "approves") {
    return { approval: "synthetic" };
  }
  if (edge.kind === "timeouts" || edge.kind === "retries") {
    return { policy: "synthetic" };
  }
  if (edge.kind === "checkpoints") {
    return { checkpoint: "synthetic" };
  }
  if (edge.kind === "reads" || edge.kind === "writes" || edge.kind === "cites") {
    return {
      access: edge.kind === "writes" ? "write" : edge.kind === "cites" ? "cite" : "read",
      memory: "session",
      key: "evidence",
      target: "session.evidence",
      sourceSpan: testSpan(1),
      targetSpan: testSpan(1),
    };
  }
  return undefined;
}

function validateSchema(schema, value) {
  const errors = [];
  validateAgainst(schema, value, schema, "$", errors);
  return errors;
}

function assertGraphEdgesResolve(graph) {
  const nodeIds = new Set(graph.nodes.map((node) => node.id));
  for (const edge of graph.edges) {
    assert.equal(nodeIds.has(edge.from), true, `missing graph edge source '${edge.from}'`);
    assert.equal(nodeIds.has(edge.to), true, `missing graph edge target '${edge.to}'`);
  }
}

function assertGraphAcyclic(graph) {
  const outgoing = new Map(graph.nodes.map((node) => [node.id, []]));
  for (const edge of graph.edges) {
    outgoing.get(edge.from)?.push(edge.to);
  }

  const visiting = new Set();
  const visited = new Set();
  const visit = (nodeId, stack) => {
    if (visiting.has(nodeId)) {
      assert.fail(`graph cycle detected: ${[...stack, nodeId].join(" -> ")}`);
    }
    if (visited.has(nodeId)) {
      return;
    }

    visiting.add(nodeId);
    for (const target of outgoing.get(nodeId) ?? []) {
      visit(target, [...stack, nodeId]);
    }
    visiting.delete(nodeId);
    visited.add(nodeId);
  };

  for (const node of graph.nodes) {
    visit(node.id, []);
  }
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
  if (typeof value === "string" && schema.minLength !== undefined && value.length < schema.minLength) {
    errors.push(`${path} length must be >= ${schema.minLength}`);
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
    assert.deepEqual(ast.imports, []);
    assert.equal(ast.goals.length, 1);
    assert.equal(ast.types.length, 3);
    assert.equal(ast.goals[0].name, "apply_code_change");
    assert.equal(ast.goals[0].steps.length, 3);
    assert.equal(ast.goals[0].memory[0].retention[0], "retain summaries until goal_complete");
    assert.equal(ast.goals[0].memory[0].retentionRules[0].subject.raw, "summaries");
    assert.equal(ast.goals[0].memory[0].retentionRules[0].until.raw, "goal_complete");
    assert.equal(ast.goals[0].context[0].source, "repo");
    assert.equal(ast.goals[0].context[0].args._0, "./");
    assert.equal(ast.goals[0].context[0].argSpans._0.start.line, 16);
    assert.equal(ast.goals[0].context[0].argSpans._0.start.column, 16);
    assert.equal(ast.goals[0].context[0].trust.zone, "trusted");
    assert.equal(ast.goals[0].steps[1].effects[0].argSpans.path.start.line, 39);
    assert.equal(ast.goals[0].steps[1].effects[0].argSpans.path.start.column, 24);
    assert.equal(ast.goals[0].capabilities[0].grants[0].raw, "read path: \"./src/**\"");
    assert.equal(ast.goals[0].capabilities[0].grants[0].span.file, VALID_CODE_CHANGE);
    assert.equal(ast.goals[0].capabilities[0].grants[0].span.start.line, 20);
    assert.equal(ast.goals[0].capabilities[0].grants[0].actionSpan.start.column, 5);
    assert.deepEqual(ast.goals[0].capabilities[0].grants[0].args.map((argument) => [argument.key, argument.value, argument.kind]), [
      ["path", "./src/**", "string"],
    ]);
    assert.equal(ast.goals[0].capabilities[0].grants[0].args[0].keySpan.start.column, 10);
    assert.equal(ast.goals[0].capabilities[0].grants[0].args[0].valueSpan.start.column, 16);
    assert.equal(ast.goals[0].span.file, VALID_CODE_CHANGE);
    assert.equal(ast.goals[0].span.start.line, 15);

    const dependencyAst = runJson(["parse", VALID_DEPENDENCY_GRAPH]);
    assert.equal(dependencyAst.goals[0].parameters[0].name, "request");
    assert.equal(dependencyAst.goals[0].parameters[0].span.start.line, 19);
    assert.equal(dependencyAst.goals[0].parameters[0].span.start.column, 30);
    assert.equal(dependencyAst.goals[0].outputTypeSpan.start.line, 19);
    assert.equal(dependencyAst.goals[0].outputTypeSpan.start.column, 55);
    assert.equal(dependencyAst.goals[0].steps[0].parameters[0].name, "input");
    assert.equal(dependencyAst.goals[0].steps[0].parameters[0].span.start.line, 37);
    assert.equal(dependencyAst.goals[0].steps[0].parameters[0].span.start.column, 22);
    assert.equal(dependencyAst.goals[0].steps[0].outputTypeSpan.start.line, 37);
    assert.equal(dependencyAst.goals[0].steps[0].outputTypeSpan.start.column, 45);

    const importAst = runJson(["parse", VALID_IMPORTS]);
    assert.equal(importAst.package.name, "fixtures.imports");
    assert.equal(importAst.imports.length, 2);
    assert.equal(importAst.imports[0].kind, "Import");
    assert.equal(importAst.imports[0].path, "std.tools");
    assert.equal(importAst.imports[0].span.start.line, 3);
    assert.equal(importAst.imports[1].path, "examples.shared.Finding");
    assert.equal(importAst.imports[1].span.start.line, 4);

    const memoryAst = runJson(["parse", VALID_MEMORY_FLOW_GRAPH]);
    assert.equal(memoryAst.goals[0].memory[0].keys[0].name, "decisions");
    assert.equal(memoryAst.goals[0].memory[0].keys[0].type, "Record");
    assert.equal(memoryAst.goals[0].steps[0].memoryAccesses[0].access, "write");
    assert.equal(memoryAst.goals[0].steps[0].memoryAccesses[0].target, "session.evidence");
    assert.equal(memoryAst.goals[0].steps[0].memoryAccesses[0].span.start.line, 22);
    assert.equal(memoryAst.goals[0].steps[1].memoryAccesses[0].access, "read");
    assert.equal(memoryAst.goals[0].steps[1].memoryAccesses[1].access, "cite");
    assert.equal(memoryAst.goals[0].steps[0].memoryAccesses[1].key, "decisions");

    const invariantAst = runJson(["parse", VALID_INVARIANT_GUARD_GRAPH]);
    assert.equal(invariantAst.goals[0].invariants[0].kind, "Require");
    assert.equal(invariantAst.goals[0].invariants[0].value, "reversible_operations_cited");
    assert.equal(invariantAst.goals[0].invariants[1].kind, "Deny");
  });

  it("emits UTF-8 byte offsets in parsed source spans", () => {
    const dir = mkdtempSync(join(tmpdir(), "intent-utf8-"));
    const file = join(dir, "utf8.intent");
    const sourceLines = [
      "package fixtures.utf8_offsets",
      "type Cafe = caf\\u00e9",
      "goal utf8_offsets() -> Cafe {",
      "  context repo(\"./\")",
      "  plan {",
      "    step emit -> Cafe",
      "  }",
      "  verify {",
      "    require no_policy_violations",
      "  }",
      "}",
    ];
    const source = sourceLines.join("\n").replace("\\u00e9", "\u00e9");
    writeFileSync(file, source, "utf8");

    try {
      const ast = runJson(["parse", file]);
      const expectedGoalOffset = Buffer.byteLength(`${sourceLines[0]}\n${sourceLines[1].replace("\\u00e9", "\u00e9")}\n`, "utf8");
      const goalCodeUnitOffset = source.indexOf("goal utf8_offsets");
      const contextCodeUnitOffset = source.indexOf("repo(\"./\")") + "repo(".length;

      assert.equal(ast.goals[0].span.start.offset, expectedGoalOffset);
      assert.equal(ast.goals[0].context[0].argSpans._0.start.offset, Buffer.byteLength(source.slice(0, contextCodeUnitOffset), "utf8"));
      assert(ast.goals[0].span.start.offset > goalCodeUnitOffset);
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
  });

  it("parses v0 comma-separated call arguments with exact keyed spans", () => {
    const dir = mkdtempSync(join(tmpdir(), "intent-call-args-"));
    const file = join(dir, "call_args.intent");
    const sourceLines = [
      "package fixtures.call_args",
      "type Report = Result",
      "goal call_args() -> Report {",
      "  context repo(\"./\", \"./docs\", mode: trusted_source)",
      "  plan {",
      "    step write -> Report {",
      "      effect FileWrite(\"./fallback\", path: \"./src/app.ts\", content: input)",
      "    }",
      "  }",
      "  verify {",
      "    require no_policy_violations",
      "  }",
      "}",
    ];
    writeFileSync(file, sourceLines.join("\n"), "utf8");

    try {
      const ast = runJson(["parse", file]);
      const context = ast.goals[0].context[0];
      const effect = ast.goals[0].steps[0].effects[0];

      assert.equal(context.args._0, "./");
      assert.equal(context.args._1, "./docs");
      assert.equal(context.args.mode, "trusted_source");
      assert.equal(context.argKinds._1, "string");
      assert.equal(context.argKinds.mode, "identifier");
      assert.equal(context.argSpans._1.start.column, sourceLines[3].indexOf("\"./docs\"") + 1);
      assert.equal(context.argSpans.mode.start.column, sourceLines[3].indexOf("mode: trusted_source") + 1);
      assert.equal(effect.args._0, "./fallback");
      assert.equal(effect.args.path, "./src/app.ts");
      assert.equal(effect.args.content, "input");
      assert.equal(effect.argKinds.content, "identifier");
      assert.equal(effect.argSpans._0.start.column, sourceLines[6].indexOf("\"./fallback\"") + 1);
      assert.equal(effect.argSpans.path.start.column, sourceLines[6].indexOf("path:") + 1);
      assert.equal(effect.argSpans.content.start.column, sourceLines[6].indexOf("content:") + 1);
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
  });

  it("normalizes v0 effect adapter aliases through explicit contracts", () => {
    const dir = mkdtempSync(join(tmpdir(), "intent-effect-contracts-"));
    const file = join(dir, "effect_contracts.intent");
    const source = [
      "package fixtures.effect_contracts",
      "type Input",
      "type Patch",
      "type Done",
      "goal effect_contracts(input: Input) -> Done {",
      "  context repo(\"./\")",
      "  context web(\"https://example.com/**\")",
      "  capability file {",
      "    write paths: [\"./src/**\", \"./generated/**\"] max_bytes: 200000",
      "  }",
      "  capability shell {",
      "    shell.exec(commands: [\"npm test\"], timeout: 5m)",
      "  }",
      "  capability web {",
      "    read domains: [\"example.com\"]",
      "  }",
      "  capability git {",
      "    git.push(branches: [\"main\"], remotes: [\"origin\"], approval: required)",
      "    commit message: \"ship fix\"",
      "  }",
      "  capability secret {",
      "    read name: \"GITHUB_TOKEN\"",
      "  }",
      "  capability ticket {",
      "    update id: \"CODE-123\"",
      "  }",
      "  capability deploy {",
      "    deploy target: \"staging\"",
      "  }",
      "  memory session {",
      "    retain evidence until goal_complete",
      "  }",
      "  plan {",
      "    step run_effects(input: Input) -> Patch {",
      "      effect Effect.FileWrite(path: \"./src/app.ts\")",
      "      effect WriteFile(\"./src/alias.ts\")",
      "      effect Command(\"npm test\")",
      "      effect WebRead(url: \"https://example.com/research\")",
      "      effect http.get(\"https://example.com/status\")",
      "      approval \"release owner approves push\"",
      "      effect git.push(branch: \"refs/heads/main\", remote: \"origin\")",
      "      effect git.commit(message: \"ship fix\")",
      "      effect SecretRead(name: \"GITHUB_TOKEN\")",
      "      effect TicketUpdate(id: \"CODE-123\")",
      "      effect Deploy(target: \"staging\")",
      "    }",
      "    step finish(input: Patch) -> Done",
      "  }",
      "  verify {",
      "    require shell(\"npm test\").exit_code == 0",
      "  }",
      "  invariant {",
      "    deny secret_write",
      "    deny production_deploy",
      "  }",
      "}",
    ].join("\n");
    writeFileSync(file, source, "utf8");

    try {
      const ast = runJson(["parse", file]);
      const check = runJson(["check", file]);
      const graph = runJson(["graph", file]);
      const effects = graph.nodes.filter((node) => node.kind === "Effect");
      const graphGrants = graph.nodes
        .filter((node) => node.kind === "Capability")
        .flatMap((capability) => capability.data.grants);
      const authorizations = effects.map((effect) => {
        return graph.edges.find((edge) => edge.kind === "authorizes" && edge.to === effect.id);
      });
      const capabilityGrants = ast.goals[0].capabilities.flatMap((capability) => capability.grants);

      assert.equal(check.ok, true);
      assert.deepEqual(check.diagnostics, []);
      assert.deepEqual(capabilityGrants.map((grant) => [grant.action, grant.key, grant.contractId, grant.contractArgument]), [
        ["write", "path", "intent.effect.file.write.v0", "path"],
        ["run", "command", "intent.effect.shell.run.v0", "command"],
        ["read", "domain", "intent.effect.web.read.v0", "domain"],
        ["push", "branch", "intent.effect.git.push.v0", "branch"],
        ["commit", "message", "intent.effect.git.commit.v0", "message"],
        ["read", "name", "intent.effect.secret.read.v0", "name"],
        ["update", "id", "intent.effect.ticket.update.v0", "id"],
        ["deploy", "target", "intent.effect.deploy.deploy.v0", "target"],
      ]);
      assert.deepEqual(graphGrants.map((grant) => [grant.action, grant.key, grant.contractId, grant.contractArgument]), capabilityGrants.map((grant) => {
        return [grant.action, grant.key, grant.contractId, grant.contractArgument];
      }));
      const gitPushGrant = capabilityGrants.find((grant) => grant.action === "push");
      assert.deepEqual(gitPushGrant.args.map((argument) => [argument.key, argument.value, argument.kind]), [
        ["branch", ["main"], "string_list"],
        ["remote", ["origin"], "string_list"],
        ["approval", "required", "identifier"],
      ]);
      assert.equal(gitPushGrant.approvalRequired, true);
      const gitPushLine = source.split("\n").find((line) => line.includes("git.push"));
      assert.equal(gitPushGrant.args[1].keySpan.start.column, gitPushLine.indexOf("remotes") + 1);
      assert.equal(gitPushGrant.args[1].valueSpan.start.column, gitPushLine.indexOf("[\"origin\"]") + 1);
      const fileWriteGrant = capabilityGrants.find((grant) => grant.action === "write");
      assert.deepEqual(fileWriteGrant.args.map((argument) => [argument.key, argument.value, argument.kind]), [
        ["path", ["./src/**", "./generated/**"], "string_list"],
        ["max_bytes", 200000, "integer"],
      ]);
      const shellGrant = capabilityGrants.find((grant) => grant.action === "run");
      assert.deepEqual(shellGrant.args.map((argument) => [argument.key, argument.value, argument.kind]), [
        ["command", ["npm test"], "string_list"],
        ["timeout", "5m", "duration"],
      ]);
      assert.deepEqual(effects.map((effect) => [effect.label, effect.data.family, effect.data.action]), [
        ["Effect.FileWrite", "file", "write"],
        ["WriteFile", "file", "write"],
        ["Command", "shell", "run"],
        ["WebRead", "web", "read"],
        ["http.get", "web", "read"],
        ["git.push", "git", "push"],
        ["git.commit", "git", "commit"],
        ["SecretRead", "secret", "read"],
        ["TicketUpdate", "ticket", "update"],
        ["Deploy", "deploy", "deploy"],
      ]);
      assert.deepEqual(effects.map((effect) => effect.data.contractId), [
        "intent.effect.file.write.v0",
        "intent.effect.file.write.v0",
        "intent.effect.shell.run.v0",
        "intent.effect.web.read.v0",
        "intent.effect.web.read.v0",
        "intent.effect.git.push.v0",
        "intent.effect.git.commit.v0",
        "intent.effect.secret.read.v0",
        "intent.effect.ticket.update.v0",
        "intent.effect.deploy.deploy.v0",
      ]);
      assert.deepEqual(effects.map((effect) => effect.data.contractArguments), [
        { path: "path" },
        { path: "_0" },
        { command: "_0" },
        { domain: "url" },
        { domain: "_0" },
        { branch: "branch", remote: "remote" },
        { message: "message" },
        { name: "name" },
        { id: "id" },
        { target: "target" },
      ]);
      assert(authorizations.every(Boolean));
      const gitCapability = graph.nodes.find((node) => node.kind === "Capability" && node.data.family === "git");
      const gitPushEffect = effects.find((effect) => effect.label === "git.push");
      assert.equal(gitCapability.data.approvalPolicy, "required");
      assert.equal(gitPushEffect.data.approvalRequired, true);
      assert.equal(graph.edges.some((edge) => edge.kind === "approves" && edge.to === gitPushEffect.id), true);
      const gitPushAuthorization = authorizations.find((edge) => edge.to === gitPushEffect.id);
      assert.deepEqual(gitPushAuthorization.data.grants.map((grant) => [grant.argument, grant.grantValue, grant.grantApprovalRequired]), [
        ["branch", ["main"], true],
        ["remote", ["origin"], true],
      ]);
      assert.equal(gitPushAuthorization.data.grants[0].grantSpan.start.line, gitPushGrant.span.start.line);
      assert.equal(gitPushAuthorization.data.grants[0].grantArgs.length, 3);
      assert.deepEqual(gitPushAuthorization.data.grants[0].grantArgs.map((argument) => [argument.key, argument.kind]), [
        ["branch", "string_list"],
        ["remote", "string_list"],
        ["approval", "identifier"],
      ]);
      assert.deepEqual(authorizations.map((edge) => edge.data.contractId), effects.map((effect) => effect.data.contractId));
      assert.deepEqual(authorizations.map((edge) => edge.data.grants.map((grant) => [grant.argument, grant.sourceArgument])), [
        [["path", "path"]],
        [["path", "_0"]],
        [["command", "_0"]],
        [["domain", "url"]],
        [["domain", "_0"]],
        [["branch", "branch"], ["remote", "remote"]],
        [["message", "message"]],
        [["name", "name"]],
        [["id", "id"]],
        [["target", "target"]],
      ]);
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
  });

  it("emits a schema-valid v0 effect adapter contract registry", () => {
    const schema = readJson(EFFECT_CONTRACT_SCHEMA);
    const registry = runJson(["contracts"]);

    assert.deepEqual(validateSchema(schema, registry), []);
    assert.equal(registry.schema_version, "intent.effect-contracts.v0");
    assert.deepEqual(registry.contracts.map((contract) => contract.id), [
      "intent.effect.file.read.v0",
      "intent.effect.file.write.v0",
      "intent.effect.shell.run.v0",
      "intent.effect.web.read.v0",
      "intent.effect.git.push.v0",
      "intent.effect.git.commit.v0",
      "intent.effect.deploy.deploy.v0",
      "intent.effect.ticket.update.v0",
      "intent.effect.secret.read.v0",
    ]);
    assert(registry.contracts.every((contract) => {
      return contract.match.exact.length + contract.match.prefix.length > 0;
    }));
    const contractsById = new Map(registry.contracts.map((contract) => [contract.id, contract]));
    assert.deepEqual(contractsById.get("intent.effect.file.read.v0").checkpoint, { requiredWhen: [], coverage: null });
    assert.equal(contractsById.get("intent.effect.file.read.v0").risk, "read_only");
    assert.deepEqual(contractsById.get("intent.effect.web.read.v0").checkpoint, { requiredWhen: [], coverage: null });
    assert.equal(contractsById.get("intent.effect.secret.read.v0").risk, "read_only");
    for (const id of [
      "intent.effect.file.write.v0",
      "intent.effect.shell.run.v0",
      "intent.effect.git.push.v0",
      "intent.effect.git.commit.v0",
      "intent.effect.deploy.deploy.v0",
      "intent.effect.ticket.update.v0",
    ]) {
      assert.equal(contractsById.get(id).risk, "irreversible");
      assert.deepEqual(contractsById.get(id).checkpoint, {
        requiredWhen: ["deny:uncheckpointed_irreversible_effect"],
        coverage: "source_order_after_effect",
      });
    }
  });

  it("rejects unsupported v0 call argument syntax", () => {
    const dir = mkdtempSync(join(tmpdir(), "intent-call-args-invalid-"));
    const file = join(dir, "invalid_call_args.intent");
    const source = [
      "package fixtures.invalid_call_args",
      "type Report = Result",
      "goal invalid_call_args() -> Report {",
      "  context repo([\"./\", invalid])",
      "  plan {",
      "    step done -> Report",
      "  }",
      "  verify {",
      "    require no_policy_violations",
      "  }",
      "}",
    ].join("\n");
    writeFileSync(file, source, "utf8");

    try {
      const result = run(["parse", file]);
      const payload = JSON.parse(result.stdout);

      assert.equal(result.status, 1);
      assert.equal(payload.diagnostics[0].code, "INTENT_PARSE_ERROR");
      assert.equal(payload.diagnostics[0].message, "unsupported list argument '[\"./\", invalid]'");
      assert.equal(payload.diagnostics[0].span.start.line, 4);
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
  });

  it("accepts valid fixtures", () => {
    const codeChange = runJson(["check", VALID_CODE_CHANGE]);
    const checkpointGraph = runJson(["check", VALID_CHECKPOINT_GRAPH]);
    const contextTrustGraph = runJson(["check", VALID_CONTEXT_TRUST_GRAPH]);
    const deployTarget = runJson(["check", VALID_DEPLOY_TARGET]);
    const dependencyGraph = runJson(["check", VALID_DEPENDENCY_GRAPH]);
    const gitCommitMessage = runJson(["check", VALID_GIT_COMMIT_MESSAGE]);
    const research = runJson(["check", VALID_RESEARCH]);
    const secretRead = runJson(["check", VALID_SECRET_READ]);
    const ticketUpdate = runJson(["check", VALID_TICKET_UPDATE]);
    const webReadWildcard = runJson(["check", VALID_WEB_READ_WILDCARD]);
    const gitPushBranch = runJson(["check", VALID_GIT_PUSH_BRANCH]);
    const irreversibleCheckpointCoverage = runJson(["check", VALID_IRREVERSIBLE_CHECKPOINT_COVERAGE]);
    const stepRequirements = runJson(["check", VALID_STEP_REQUIREMENTS]);
    const invariantGuardGraph = runJson(["check", VALID_INVARIANT_GUARD_GRAPH]);
    const imports = runJson(["check", VALID_IMPORTS]);
    const memoryFlowGraph = runJson(["check", VALID_MEMORY_FLOW_GRAPH]);
    const stepApprovalGraph = runJson(["check", VALID_STEP_APPROVAL_GRAPH]);
    const stepPolicyGraph = runJson(["check", VALID_STEP_POLICY_GRAPH]);
    const trustFlow = runJson(["check", VALID_TRUST_FLOW_SHELL_LITERAL]);

    assert.equal(codeChange.ok, true);
    assert.deepEqual(codeChange.diagnostics, []);
    assert.equal(checkpointGraph.ok, true);
    assert.deepEqual(checkpointGraph.diagnostics, []);
    assert.equal(contextTrustGraph.ok, true);
    assert.deepEqual(contextTrustGraph.diagnostics, []);
    assert.equal(deployTarget.ok, true);
    assert.deepEqual(deployTarget.diagnostics, []);
    assert.equal(dependencyGraph.ok, true);
    assert.deepEqual(dependencyGraph.diagnostics, []);
    assert.equal(gitCommitMessage.ok, true);
    assert.deepEqual(gitCommitMessage.diagnostics, []);
    assert.equal(research.ok, true);
    assert.deepEqual(research.diagnostics, []);
    assert.equal(secretRead.ok, true);
    assert.deepEqual(secretRead.diagnostics, []);
    assert.equal(ticketUpdate.ok, true);
    assert.deepEqual(ticketUpdate.diagnostics, []);
    assert.equal(webReadWildcard.ok, true);
    assert.deepEqual(webReadWildcard.diagnostics, []);
    assert.equal(gitPushBranch.ok, true);
    assert.deepEqual(gitPushBranch.diagnostics, []);
    assert.equal(irreversibleCheckpointCoverage.ok, true);
    assert.deepEqual(irreversibleCheckpointCoverage.diagnostics, []);
    assert.equal(stepRequirements.ok, true);
    assert.deepEqual(stepRequirements.diagnostics, []);
    assert.equal(invariantGuardGraph.ok, true);
    assert.deepEqual(invariantGuardGraph.diagnostics, []);
    assert.equal(imports.ok, true);
    assert.deepEqual(imports.diagnostics, []);
    assert.equal(memoryFlowGraph.ok, true);
    assert.deepEqual(memoryFlowGraph.diagnostics, []);
    assert.equal(stepApprovalGraph.ok, true);
    assert.deepEqual(stepApprovalGraph.diagnostics, []);
    assert.equal(stepPolicyGraph.ok, true);
    assert.deepEqual(stepPolicyGraph.diagnostics, []);
    assert.equal(trustFlow.ok, true);
    assert.deepEqual(trustFlow.diagnostics, []);
  });

  it("accepts executable examples", () => {
    for (const example of EXECUTABLE_EXAMPLES) {
      const ast = runJson(["parse", example]);
      const check = runJson(["check", example]);
      const graph = runJson(["graph", example]);

      assert.equal(ast.package.name.startsWith("examples."), true);
      assert.equal(check.ok, true, example);
      assert.deepEqual(check.diagnostics, []);
      assert.equal(graph.ok, true, example);
      assert.deepEqual(graph.diagnostics, []);
      assertGraphEdgesResolve(graph);
      assertGraphAcyclic(graph);
    }
  });

  it("rejects effectful goals without verification", () => {
    const result = run(["check", INVALID_MISSING_VERIFICATION]);
    const payload = JSON.parse(result.stdout);

    assert.equal(result.status, 1);
    assert.equal(payload.ok, false);
    assert.equal(payload.diagnostics[0].code, "INTENT_VERIFY_MISSING");
  });

  it("rejects source files without goals", () => {
    const result = run(["check", INVALID_GOAL_MISSING]);
    const payload = JSON.parse(result.stdout);

    assert.equal(result.status, 1);
    assert.equal(payload.ok, false);
    assert.equal(payload.diagnostics[0].code, "INTENT_GOAL_MISSING");
    assert.equal(payload.diagnostics[0].span.start.line, 1);
    assert.equal(payload.diagnostics[0].span.start.column, 1);
  });

  it("rejects invalid file declaration shape", () => {
    const missingPackage = run(["parse", INVALID_MISSING_PACKAGE]);
    const duplicatePackage = run(["parse", INVALID_DUPLICATE_PACKAGE]);
    const importAfterType = run(["parse", INVALID_IMPORT_AFTER_TYPE]);
    const emptyTypeDefinition = run(["parse", INVALID_EMPTY_TYPE_DEFINITION]);

    const missingPayload = JSON.parse(missingPackage.stdout);
    const duplicatePayload = JSON.parse(duplicatePackage.stdout);
    const importPayload = JSON.parse(importAfterType.stdout);
    const emptyTypePayload = JSON.parse(emptyTypeDefinition.stdout);

    assert.equal(missingPackage.status, 1);
    assert.equal(missingPayload.diagnostics[0].code, "INTENT_PARSE_ERROR");
    assert.match(missingPayload.diagnostics[0].message, /expected package declaration/);
    assert.equal(duplicatePackage.status, 1);
    assert.equal(duplicatePayload.diagnostics[0].code, "INTENT_PARSE_ERROR");
    assert.match(duplicatePayload.diagnostics[0].message, /duplicate package declaration/);
    assert.equal(importAfterType.status, 1);
    assert.equal(importPayload.diagnostics[0].code, "INTENT_PARSE_ERROR");
    assert.match(importPayload.diagnostics[0].message, /import declarations must appear before type or goal declarations/);
    assert.equal(emptyTypeDefinition.status, 1);
    assert.equal(emptyTypePayload.diagnostics[0].code, "INTENT_PARSE_ERROR");
    assert.match(emptyTypePayload.diagnostics[0].message, /empty definition/);
    assert.equal(emptyTypePayload.diagnostics[0].span.start.line, 3);
  });

  it("rejects effects without matching capabilities", () => {
    const result = run(["check", INVALID_UNDECLARED_EFFECT]);
    const payload = JSON.parse(result.stdout);

    assert.equal(result.status, 1);
    assert.equal(payload.ok, false);
    assert.equal(payload.diagnostics[0].code, "INTENT_EFFECT_UNDECLARED");
    assert.equal(payload.diagnostics[0].effect, "GitPush");
  });

  it("rejects effects without a v0 adapter contract before capability matching", () => {
    const result = run(["check", INVALID_UNKNOWN_EFFECT_CONTRACT]);
    const payload = JSON.parse(result.stdout);

    assert.equal(result.status, 1);
    assert.equal(payload.ok, false);
    assert.equal(payload.diagnostics.length, 1);
    assert.equal(payload.diagnostics[0].code, "INTENT_EFFECT_UNKNOWN");
    assert.equal(payload.diagnostics[0].effect, "Notify");
    assert.equal(payload.diagnostics[0].family, "notify");
    assert.equal(payload.diagnostics[0].action, null);
    assert.equal(payload.diagnostics[0].step, "notify_human");
    assert.equal(payload.diagnostics[0].span.start.line, 12);
    assert.equal(payload.diagnostics[0].span.start.column, 7);
  });

  it("rejects non-string constrained effect arguments before capability matching", () => {
    const result = run(["check", INVALID_EFFECT_ARGUMENT_TYPE]);
    const payload = JSON.parse(result.stdout);

    assert.equal(result.status, 1);
    assert.equal(payload.ok, false);
    assert.equal(payload.diagnostics.length, 1);
    assert.equal(payload.diagnostics[0].code, "INTENT_EFFECT_ARGUMENT_INVALID");
    assert.equal(payload.diagnostics[0].effect, "ShellExec");
    assert.equal(payload.diagnostics[0].family, "shell");
    assert.equal(payload.diagnostics[0].action, "run");
    assert.equal(payload.diagnostics[0].argument, "command");
    assert.equal(payload.diagnostics[0].value, "30");
    assert.equal(payload.diagnostics[0].kind, "integer");
    assert.equal(payload.diagnostics[0].span.start.line, 11);
    assert.equal(payload.diagnostics[0].span.start.column, 24);
  });

  it("rejects file writes outside declared path grants", () => {
    const result = run(["check", INVALID_FILE_WRITE_OUTSIDE_CAPABILITY]);
    const payload = JSON.parse(result.stdout);

    assert.equal(result.status, 1);
    assert.equal(payload.ok, false);
    assert.equal(payload.diagnostics[0].code, "INTENT_CAPABILITY_DENIED");
    assert.equal(payload.diagnostics[0].argument, "path");
    assert.equal(payload.diagnostics[0].value, "./README.md");
    assert.equal(payload.diagnostics[0].span.start.line, 27);
    assert.equal(payload.diagnostics[0].span.start.column, 24);
  });

  it("rejects absolute file paths outside the package root", () => {
    const result = run(["check", INVALID_FILE_WRITE_ABSOLUTE_PATH]);
    const payload = JSON.parse(result.stdout);

    assert.equal(result.status, 1);
    assert.equal(payload.ok, false);
    assert.equal(payload.diagnostics[0].code, "INTENT_CAPABILITY_DENIED");
    assert.equal(payload.diagnostics[0].argument, "path");
    assert.equal(payload.diagnostics[0].value, "/etc/passwd");
    assert.deepEqual(payload.diagnostics[0].allowed, ["/**"]);
    assert.equal(payload.diagnostics[0].span.start.line, 20);
    assert.equal(payload.diagnostics[0].span.start.column, 24);
  });

  it("rejects shell commands outside declared command grants", () => {
    const result = run(["check", INVALID_SHELL_EXEC_OUTSIDE_CAPABILITY]);
    const payload = JSON.parse(result.stdout);

    assert.equal(result.status, 1);
    assert.equal(payload.ok, false);
    assert.equal(payload.diagnostics[0].code, "INTENT_CAPABILITY_DENIED");
    assert.equal(payload.diagnostics[0].argument, "command");
    assert.equal(payload.diagnostics[0].value, "npm run lint");
    assert.equal(payload.diagnostics[0].span.start.line, 30);
    assert.equal(payload.diagnostics[0].span.start.column, 24);
  });

  it("rejects secret reads outside declared name grants", () => {
    const result = run(["check", INVALID_SECRET_READ_OUTSIDE_CAPABILITY]);
    const payload = JSON.parse(result.stdout);

    assert.equal(result.status, 1);
    assert.equal(payload.ok, false);
    assert.equal(payload.diagnostics[0].code, "INTENT_CAPABILITY_DENIED");
    assert.equal(payload.diagnostics[0].effect, "SecretRead");
    assert.equal(payload.diagnostics[0].argument, "name");
    assert.equal(payload.diagnostics[0].value, "AWS_TOKEN");
    assert.deepEqual(payload.diagnostics[0].allowed, ["GITHUB_TOKEN"]);
  });

  it("rejects ticket updates outside declared id grants", () => {
    const result = run(["check", INVALID_TICKET_UPDATE_OUTSIDE_CAPABILITY]);
    const payload = JSON.parse(result.stdout);

    assert.equal(result.status, 1);
    assert.equal(payload.ok, false);
    assert.equal(payload.diagnostics[0].code, "INTENT_CAPABILITY_DENIED");
    assert.equal(payload.diagnostics[0].effect, "TicketUpdate");
    assert.equal(payload.diagnostics[0].argument, "id");
    assert.equal(payload.diagnostics[0].value, "CODE-999");
    assert.deepEqual(payload.diagnostics[0].allowed, ["CODE-123"]);
  });

  it("rejects deploys outside declared target grants", () => {
    const result = run(["check", INVALID_DEPLOY_TARGET_OUTSIDE_CAPABILITY]);
    const payload = JSON.parse(result.stdout);

    assert.equal(result.status, 1);
    assert.equal(payload.ok, false);
    assert.equal(payload.diagnostics[0].code, "INTENT_CAPABILITY_DENIED");
    assert.equal(payload.diagnostics[0].effect, "Deploy");
    assert.equal(payload.diagnostics[0].argument, "target");
    assert.equal(payload.diagnostics[0].value, "production");
    assert.deepEqual(payload.diagnostics[0].allowed, ["staging"]);
  });

  it("rejects deploys denied by production invariants", () => {
    const result = run(["check", INVALID_INVARIANT_PRODUCTION_DEPLOY]);
    const payload = JSON.parse(result.stdout);

    assert.equal(result.status, 1);
    assert.equal(payload.ok, false);
    assert.equal(payload.diagnostics[0].code, "INTENT_INVARIANT_VIOLATION");
    assert.equal(payload.diagnostics[0].invariant, "production_deploy");
    assert.equal(payload.diagnostics[0].effect, "Deploy");
    assert.equal(payload.diagnostics[0].argument, "target");
    assert.equal(payload.diagnostics[0].value, "production");
    assert.equal(payload.diagnostics[0].span.start.line, 35);
    assert.equal(payload.diagnostics[0].effect_span.start.line, 26);
    assert.equal(payload.diagnostics[0].effect_span.start.column, 21);
  });

  it("rejects file writes denied by secret write invariants", () => {
    const result = run(["check", INVALID_INVARIANT_SECRET_WRITE]);
    const payload = JSON.parse(result.stdout);

    assert.equal(result.status, 1);
    assert.equal(payload.ok, false);
    assert.equal(payload.diagnostics[0].code, "INTENT_INVARIANT_VIOLATION");
    assert.equal(payload.diagnostics[0].invariant, "secret_write");
    assert.equal(payload.diagnostics[0].effect, "FileWrite");
    assert.equal(payload.diagnostics[0].argument, "path");
    assert.equal(payload.diagnostics[0].value, "./.env");
    assert.equal(payload.diagnostics[0].span.start.line, 46);
    assert.equal(payload.diagnostics[0].effect_span.start.line, 34);
    assert.equal(payload.diagnostics[0].effect_span.start.column, 24);
  });

  it("rejects file writes denied by unrelated file invariants", () => {
    const result = run(["check", INVALID_INVARIANT_UNRELATED_FILE_WRITE]);
    const payload = JSON.parse(result.stdout);

    assert.equal(result.status, 1);
    assert.equal(payload.ok, false);
    assert.equal(payload.diagnostics[0].code, "INTENT_INVARIANT_VIOLATION");
    assert.equal(payload.diagnostics[0].invariant, "unrelated_file_write");
    assert.equal(payload.diagnostics[0].effect, "FileWrite");
    assert.equal(payload.diagnostics[0].argument, "path");
    assert.equal(payload.diagnostics[0].value, "./docs/readme.md");
    assert.equal(payload.diagnostics[0].span.start.line, 35);
    assert.equal(payload.diagnostics[0].effect_span.start.line, 26);
    assert.equal(payload.diagnostics[0].effect_span.start.column, 24);
  });

  it("rejects git commits outside declared message grants", () => {
    const result = run(["check", INVALID_GIT_COMMIT_MESSAGE_MISMATCH]);
    const payload = JSON.parse(result.stdout);

    assert.equal(result.status, 1);
    assert.equal(payload.ok, false);
    assert.equal(payload.diagnostics[0].code, "INTENT_CAPABILITY_DENIED");
    assert.equal(payload.diagnostics[0].effect, "GitCommit");
    assert.equal(payload.diagnostics[0].argument, "message");
    assert.equal(payload.diagnostics[0].value, "release fix");
    assert.deepEqual(payload.diagnostics[0].allowed, ["ship fix"]);
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

  it("rejects context sources outside declared read capabilities", () => {
    const result = run(["check", INVALID_CONTEXT_SOURCE_OUTSIDE_CAPABILITY]);
    const payload = JSON.parse(result.stdout);

    assert.equal(result.status, 1);
    assert.equal(payload.ok, false);
    assert.equal(payload.diagnostics[0].code, "INTENT_CONTEXT_UNDECLARED");
    assert.equal(payload.diagnostics[0].source, "web");
    assert.equal(payload.diagnostics[0].argument, "domain");
    assert.equal(payload.diagnostics[0].value, "outside.example.org");
    assert.deepEqual(payload.diagnostics[0].allowed, ["example.com"]);
    assert.equal(payload.diagnostics[0].span.start.line, 13);
    assert.equal(payload.diagnostics[0].span.start.column, 15);
  });

  it("rejects non-string context source arguments before capability matching", () => {
    const result = run(["check", INVALID_CONTEXT_ARGUMENT_TYPE]);
    const payload = JSON.parse(result.stdout);

    assert.equal(result.status, 1);
    assert.equal(payload.ok, false);
    assert.equal(payload.diagnostics.length, 1);
    assert.equal(payload.diagnostics[0].code, "INTENT_CONTEXT_ARGUMENT_INVALID");
    assert.equal(payload.diagnostics[0].context, "web(url: 30)");
    assert.equal(payload.diagnostics[0].source, "web");
    assert.equal(payload.diagnostics[0].family, "web");
    assert.equal(payload.diagnostics[0].action, "read");
    assert.equal(payload.diagnostics[0].argument, "domain");
    assert.equal(payload.diagnostics[0].value, "30");
    assert.equal(payload.diagnostics[0].kind, "integer");
    assert.equal(payload.diagnostics[0].span.start.line, 6);
    assert.equal(payload.diagnostics[0].span.start.column, 15);
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

  it("rejects approval-required effects without a step approval gate", () => {
    const result = run(["check", INVALID_APPROVAL_REQUIRED_MISSING]);
    const payload = JSON.parse(result.stdout);

    assert.equal(result.status, 1);
    assert.equal(payload.ok, false);
    assert.equal(payload.diagnostics[0].code, "INTENT_APPROVAL_MISSING");
    assert.equal(payload.diagnostics[0].effect, "GitPush");
    assert.equal(payload.diagnostics[0].capability, "git");
    assert.equal(payload.diagnostics[0].step, "push_release");
    assert.equal(payload.diagnostics.length, 1);
  });

  it("rejects grant-level approval-required effects without a step approval gate", () => {
    const dir = mkdtempSync(join(tmpdir(), "intent-grant-approval-missing-"));
    const file = join(dir, "grant_approval_missing.intent");
    const source = [
      "package fixtures.grant_approval_missing",
      "type Patch",
      "type GitRef",
      "goal grant_approval_missing() -> GitRef {",
      "  context repo(\"./\")",
      "  capability git {",
      "    git.push(branches: [\"main\"], remotes: [\"origin\"], approval: required)",
      "  }",
      "  memory session {",
      "    retain approvals until goal_complete",
      "  }",
      "  plan {",
      "    step prepare -> Patch",
      "    step push_release(input: Patch) -> GitRef {",
      "      effect git.push(branch: \"main\", remote: \"origin\")",
      "    }",
      "  }",
      "  verify {",
      "    require no_policy_violations",
      "  }",
      "  invariant {",
      "    deny secret_write",
      "    deny unrelated_file_write",
      "  }",
      "}",
    ].join("\n");
    writeFileSync(file, source, "utf8");

    try {
      const result = run(["check", file]);
      const payload = JSON.parse(result.stdout);

      assert.equal(result.status, 1);
      assert.equal(payload.ok, false);
      assert.equal(payload.diagnostics[0].code, "INTENT_APPROVAL_MISSING");
      assert.equal(payload.diagnostics[0].effect, "git.push");
      assert.equal(payload.diagnostics[0].capability, "git");
      assert.equal(payload.diagnostics[0].step, "push_release");
      assert.equal(payload.diagnostics.length, 1);
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
  });

  it("rejects nonliteral shell commands as unsafe trust flow", () => {
    const result = run(["check", INVALID_TRUST_FLOW_UNTRUSTED_SHELL_INPUT]);
    const payload = JSON.parse(result.stdout);

    assert.equal(result.status, 1);
    assert.equal(payload.ok, false);
    assert.equal(payload.diagnostics[0].code, "INTENT_TRUST_FLOW_UNSAFE");
    assert.equal(payload.diagnostics[0].argument, "command");
    assert.equal(payload.diagnostics[0].trust, "untrusted");
    assert.equal(payload.diagnostics[0].span.start.line, 32);
    assert.equal(payload.diagnostics[0].span.start.column, 24);
    assert.equal(payload.diagnostics.length, 1);
  });

  it("rejects nonliteral constrained effect sink arguments as unsafe trust flow", () => {
    const result = run(["check", INVALID_TRUST_FLOW_UNTRUSTED_EFFECT_SINKS]);
    const payload = JSON.parse(result.stdout);

    assert.equal(result.status, 1);
    assert.equal(payload.ok, false);
    assert.deepEqual(payload.diagnostics.map((diagnostic) => diagnostic.code), [
      "INTENT_TRUST_FLOW_UNSAFE",
      "INTENT_TRUST_FLOW_UNSAFE",
      "INTENT_TRUST_FLOW_UNSAFE",
      "INTENT_TRUST_FLOW_UNSAFE",
      "INTENT_TRUST_FLOW_UNSAFE",
      "INTENT_TRUST_FLOW_UNSAFE",
    ]);
    assert.deepEqual(payload.diagnostics.map((diagnostic) => diagnostic.argument), [
      "path",
      "name",
      "id",
      "target",
      "branch",
      "message",
    ]);
    assert.deepEqual(payload.diagnostics.map((diagnostic) => diagnostic.value), [
      "input",
      "input",
      "input",
      "input",
      "input",
      "input",
    ]);
    assert(payload.diagnostics.every((diagnostic) => diagnostic.trust === "untrusted"));
    assert.equal(payload.diagnostics[0].span.start.line, 49);
    assert.equal(payload.diagnostics[0].span.start.column, 24);
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
    assert.equal(payload.diagnostics[0].span.start.line, 44);
    assert.equal(payload.diagnostics[0].span.start.column, 19);
  });

  it("rejects side-effect calls inside verification requirements", () => {
    const result = run(["check", INVALID_VERIFY_IMPURE_FILE_WRITE]);
    const customResult = run(["check", INVALID_VERIFY_IMPURE_CUSTOM_EFFECT]);
    const payload = JSON.parse(result.stdout);
    const customPayload = JSON.parse(customResult.stdout);

    assert.equal(result.status, 1);
    assert.equal(payload.ok, false);
    assert.equal(payload.diagnostics[0].code, "INTENT_VERIFY_IMPURE");
    assert.equal(payload.diagnostics[0].requirement, "FileWrite(path: \"./src/app.ts\")");
    assert.equal(payload.diagnostics[0].effect, "FileWrite");
    assert.equal(payload.diagnostics[0].family, "file");
    assert.equal(payload.diagnostics[0].action, "write");
    assert.equal(payload.diagnostics[0].span.start.line, 46);
    assert.equal(payload.diagnostics[0].span.start.column, 13);
    assert.equal(payload.diagnostics[0].span.end.column, 44);

    assert.equal(customResult.status, 1);
    assert.equal(customPayload.ok, false);
    assert.equal(customPayload.diagnostics[0].code, "INTENT_VERIFY_IMPURE");
    assert.equal(customPayload.diagnostics[0].requirement, "notify.send(channel: \"alerts\")");
    assert.equal(customPayload.diagnostics[0].effect, "notify.send");
    assert.equal(customPayload.diagnostics[0].family, "notify");
    assert.equal(customPayload.diagnostics[0].action, null);
    assert.equal(customPayload.diagnostics[0].span.start.line, 13);
    assert.equal(customPayload.diagnostics[0].span.start.column, 13);
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

  it("rejects memory retention rules with unsupported lifecycle targets", () => {
    const result = run(["check", INVALID_MEMORY_RETENTION_UNKNOWN_UNTIL]);
    const payload = JSON.parse(result.stdout);

    assert.equal(result.status, 1);
    assert.equal(payload.ok, false);
    assert.equal(payload.diagnostics[0].code, "INTENT_MEMORY_RETENTION_INVALID");
    assert.equal(payload.diagnostics[0].retention, "retain evidence until forever");
    assert.equal(payload.diagnostics[0].until, "forever");
  });

  it("rejects undeclared memory access", () => {
    const result = run(["check", INVALID_MEMORY_ACCESS_UNDECLARED]);
    const payload = JSON.parse(result.stdout);

    assert.equal(result.status, 1);
    assert.equal(payload.ok, false);
    assert.equal(payload.diagnostics[0].code, "INTENT_MEMORY_UNDECLARED");
    assert.equal(payload.diagnostics[0].step, "inspect");
    assert.equal(payload.diagnostics[0].memory, "archive");
    assert.equal(payload.diagnostics[0].access, "read");
    assert.equal(payload.diagnostics[0].target, "archive.evidence");
  });

  it("rejects undeclared memory keys", () => {
    const result = run(["check", INVALID_MEMORY_KEY_UNDECLARED]);
    const payload = JSON.parse(result.stdout);

    assert.equal(result.status, 1);
    assert.equal(payload.ok, false);
    assert.equal(payload.diagnostics[0].code, "INTENT_MEMORY_KEY_UNDECLARED");
    assert.equal(payload.diagnostics[0].step, "draft");
    assert.equal(payload.diagnostics[0].memory, "session");
    assert.equal(payload.diagnostics[0].key, "evidence");
    assert.equal(payload.diagnostics[0].target, "session.evidence");
    assert.deepEqual(payload.diagnostics[0].declared_keys, ["summaries"]);
  });

  it("rejects completion provenance requirements without final-step citations", () => {
    const result = run(["check", INVALID_PROVENANCE_MISSING]);
    const payload = JSON.parse(result.stdout);

    assert.equal(result.status, 1);
    assert.equal(payload.ok, false);
    assert.equal(payload.diagnostics[0].code, "INTENT_PROVENANCE_MISSING");
    assert.deepEqual(payload.diagnostics[0].requirements, ["all_outputs_cited"]);
    assert.deepEqual(payload.diagnostics[0].invariants, ["uncited_external_claim"]);
    assert.equal(payload.diagnostics[0].citations, 0);
  });

  it("rejects completion citations without earlier memory writes", () => {
    const result = run(["check", INVALID_PROVENANCE_UNBACKED]);
    const payload = JSON.parse(result.stdout);

    assert.equal(result.status, 1);
    assert.equal(payload.ok, false);
    assert.equal(payload.diagnostics[0].code, "INTENT_PROVENANCE_UNBACKED");
    assert.equal(payload.diagnostics[0].citations, 1);
    assert.equal(payload.diagnostics[0].unbacked_citations[0].target, "session.evidence");
    assert.equal(payload.diagnostics[0].unbacked_citations[0].step, "draft");
  });

  it("rejects completion checkpoint requirements without final-step checkpoints", () => {
    const result = run(["check", INVALID_COMPLETION_CHECKPOINT_MISSING]);
    const payload = JSON.parse(result.stdout);

    assert.equal(result.status, 1);
    assert.equal(payload.ok, false);
    assert.equal(payload.diagnostics[0].code, "INTENT_CHECKPOINT_MISSING");
    assert.equal(payload.diagnostics[0].step, "draft_report");
    assert.deepEqual(payload.diagnostics[0].requirements, ["final_state_checkpointed"]);
    assert.deepEqual(payload.diagnostics[0].invariants, []);
    assert.equal(payload.diagnostics[0].checkpoints, 0);
  });

  it("rejects irreversible effects without a following checkpoint", () => {
    const result = run(["check", INVALID_UNCHECKPOINTED_IRREVERSIBLE_EFFECT]);
    const payload = JSON.parse(result.stdout);

    assert.equal(result.status, 1);
    assert.equal(payload.ok, false);
    assert.equal(payload.diagnostics[0].code, "INTENT_CHECKPOINT_MISSING");
    assert.equal(payload.diagnostics[0].step, "publish_release");
    assert.equal(payload.diagnostics[0].invariant, "uncheckpointed_irreversible_effect");
    assert.equal(payload.diagnostics[0].effect, "GitPush");
    assert.equal(payload.diagnostics[0].family, "git");
    assert.equal(payload.diagnostics[0].action, "push");
    assert.equal(payload.diagnostics[0].contract_id, "intent.effect.git.push.v0");
    assert.equal(payload.diagnostics[0].checkpoint_coverage, "source_order_after_effect");
    assert.equal(payload.diagnostics[0].checkpoints_after_effect, 0);
  });

  it("rejects checkpoints that appear before irreversible effects", () => {
    const result = run(["check", INVALID_IRREVERSIBLE_CHECKPOINT_BEFORE_EFFECT]);
    const payload = JSON.parse(result.stdout);

    assert.equal(result.status, 1);
    assert.equal(payload.ok, false);
    assert.equal(payload.diagnostics[0].code, "INTENT_CHECKPOINT_MISSING");
    assert.equal(payload.diagnostics[0].step, "publish_release");
    assert.equal(payload.diagnostics[0].effect, "GitPush");
    assert.equal(payload.diagnostics[0].checkpoint_coverage, "source_order_after_effect");
    assert.equal(payload.diagnostics[0].checkpoints_after_effect, 0);
  });

  it("rejects invalid step policy syntax", () => {
    const result = run(["check", INVALID_STEP_POLICY_BAD_TIMEOUT]);
    const payload = JSON.parse(result.stdout);

    assert.equal(result.status, 1);
    assert.equal(payload.ok, false);
    assert.equal(payload.diagnostics[0].code, "INTENT_POLICY_INVALID");
    assert.equal(payload.diagnostics[0].step, "patch_code");
    assert.equal(payload.diagnostics[0].policyKind, "timeout");
    assert.equal(payload.diagnostics[0].policy, "soon");
  });

  it("rejects empty step checkpoint labels", () => {
    const result = run(["check", INVALID_CHECKPOINT_EMPTY]);
    const payload = JSON.parse(result.stdout);

    assert.equal(result.status, 1);
    assert.equal(payload.ok, false);
    assert.equal(payload.diagnostics[0].code, "INTENT_CHECKPOINT_INVALID");
    assert.equal(payload.diagnostics[0].step, "patch_code");
    assert.equal(payload.diagnostics[0].checkpoint, "");
  });

  it("rejects empty step approval gate labels", () => {
    const result = run(["check", INVALID_APPROVAL_EMPTY]);
    const payload = JSON.parse(result.stdout);

    assert.equal(result.status, 1);
    assert.equal(payload.ok, false);
    assert.equal(payload.diagnostics[0].code, "INTENT_APPROVAL_INVALID");
    assert.equal(payload.diagnostics[0].step, "patch_code");
    assert.equal(payload.diagnostics[0].approval, "");
  });

  it("rejects unresolved type references", () => {
    const result = run(["check", INVALID_UNRESOLVED_TYPE]);
    const payload = JSON.parse(result.stdout);

    assert.equal(result.status, 1);
    assert.equal(payload.ok, false);
    assert.equal(payload.diagnostics[0].code, "INTENT_TYPE_UNRESOLVED");
    assert.equal(payload.diagnostics[0].type, "MissingType");
    assert.equal(payload.diagnostics[0].span.start.line, 16);
    assert.equal(payload.diagnostics[0].span.start.column, 25);
  });

  it("rejects goal output type mismatches", () => {
    const result = run(["check", INVALID_GOAL_OUTPUT_TYPE_MISMATCH]);
    const payload = JSON.parse(result.stdout);

    assert.equal(result.status, 1);
    assert.equal(payload.ok, false);
    assert.equal(payload.diagnostics[0].code, "INTENT_TYPE_MISMATCH");
    assert.equal(payload.diagnostics[0].goal, "produce_expected_report");
    assert.equal(payload.diagnostics[0].step, "prepare_patch");
    assert.equal(payload.diagnostics[0].expected, "ExpectedReport");
    assert.equal(payload.diagnostics[0].actual, "DraftPatch");
    assert.equal(payload.diagnostics[0].span.start.line, 20);
    assert.equal(payload.diagnostics[0].span.start.column, 23);
  });

  it("rejects duplicate step names", () => {
    const result = run(["check", INVALID_DUPLICATE_STEP_NAME]);
    const payload = JSON.parse(result.stdout);

    assert.equal(result.status, 1);
    assert.equal(payload.ok, false);
    assert.equal(payload.diagnostics[0].code, "INTENT_NAME_DUPLICATE");
    assert.equal(payload.diagnostics[0].name, "inspect_request");
  });

  it("rejects duplicate top-level names", () => {
    const duplicateGoal = run(["check", INVALID_DUPLICATE_GOAL_NAME]);
    const duplicateGoalPayload = JSON.parse(duplicateGoal.stdout);
    const duplicateType = run(["check", INVALID_DUPLICATE_TYPE_NAME]);
    const duplicateTypePayload = JSON.parse(duplicateType.stdout);

    assert.equal(duplicateGoal.status, 1);
    assert.equal(duplicateGoalPayload.ok, false);
    assert.equal(duplicateGoalPayload.diagnostics[0].code, "INTENT_NAME_DUPLICATE");
    assert.equal(duplicateGoalPayload.diagnostics[0].name, "duplicate_goal");
    assert.equal(duplicateGoalPayload.diagnostics[0].span.start.line, 33);
    assert.equal(duplicateGoalPayload.diagnostics[0].previous_span.start.line, 7);

    assert.equal(duplicateType.status, 1);
    assert.equal(duplicateTypePayload.ok, false);
    assert.equal(duplicateTypePayload.diagnostics[0].code, "INTENT_NAME_DUPLICATE");
    assert.equal(duplicateTypePayload.diagnostics[0].name, "Finding");
    assert.equal(duplicateTypePayload.diagnostics[0].span.start.line, 7);
    assert.equal(duplicateTypePayload.diagnostics[0].previous_span.start.line, 3);
  });

  it("rejects duplicate parameter names", () => {
    const duplicateGoalInput = run(["check", INVALID_DUPLICATE_GOAL_INPUT]);
    const duplicateGoalInputPayload = JSON.parse(duplicateGoalInput.stdout);
    const duplicateStepInput = run(["check", INVALID_DUPLICATE_STEP_INPUT]);
    const duplicateStepInputPayload = JSON.parse(duplicateStepInput.stdout);

    assert.equal(duplicateGoalInput.status, 1);
    assert.equal(duplicateGoalInputPayload.ok, false);
    assert.equal(duplicateGoalInputPayload.diagnostics[0].code, "INTENT_NAME_DUPLICATE");
    assert.equal(duplicateGoalInputPayload.diagnostics[0].name, "input");
    assert.equal(duplicateGoalInputPayload.diagnostics[0].span.start.line, 7);
    assert.equal(duplicateGoalInputPayload.diagnostics[0].span.start.column, 51);
    assert.equal(duplicateGoalInputPayload.diagnostics[0].previous_span.start.column, 35);

    assert.equal(duplicateStepInput.status, 1);
    assert.equal(duplicateStepInputPayload.ok, false);
    assert.equal(duplicateStepInputPayload.diagnostics[0].code, "INTENT_NAME_DUPLICATE");
    assert.equal(duplicateStepInputPayload.diagnostics[0].name, "input");
    assert.equal(duplicateStepInputPayload.diagnostics[0].span.start.line, 28);
    assert.equal(duplicateStepInputPayload.diagnostics[0].span.start.column, 35);
    assert.equal(duplicateStepInputPayload.diagnostics[0].previous_span.start.column, 19);
  });

  it("rejects unsupported goal statements", () => {
    const result = run(["check", INVALID_UNSUPPORTED_GOAL_STATEMENT]);
    const payload = JSON.parse(result.stdout);

    assert.equal(result.status, 1);
    assert.equal(payload.ok, false);
    assert.equal(payload.diagnostics[0].code, "INTENT_UNSUPPORTED_SYNTAX");
    assert.equal(payload.diagnostics[0].syntax, "delegate reviewer");
    assert.equal(payload.diagnostics[0].goal, "reject_unsupported_goal_statement");
    assert.equal(payload.diagnostics[0].span.start.line, 18);
    assert.equal(payload.diagnostics[0].span.start.column, 3);
  });

  it("rejects unsupported plan, step, verify, and invariant statements", () => {
    const plan = run(["check", INVALID_UNSUPPORTED_PLAN_STATEMENT]);
    const step = run(["check", INVALID_UNSUPPORTED_STEP_STATEMENT]);
    const verify = run(["check", INVALID_UNSUPPORTED_VERIFY_STATEMENT]);
    const invariant = run(["check", INVALID_UNSUPPORTED_INVARIANT_STATEMENT]);
    const planPayload = JSON.parse(plan.stdout);
    const stepPayload = JSON.parse(step.stdout);
    const verifyPayload = JSON.parse(verify.stdout);
    const invariantPayload = JSON.parse(invariant.stdout);

    assert.equal(plan.status, 1);
    assert.equal(planPayload.ok, false);
    assert.equal(planPayload.diagnostics[0].code, "INTENT_UNSUPPORTED_SYNTAX");
    assert.equal(planPayload.diagnostics[0].syntax, "delegate reviewer");
    assert.equal(planPayload.diagnostics[0].block, "plan");
    assert.equal(planPayload.diagnostics[0].span.start.line, 9);
    assert.equal(planPayload.diagnostics[0].span.start.column, 5);

    assert.equal(step.status, 1);
    assert.equal(stepPayload.ok, false);
    assert.equal(stepPayload.diagnostics[0].code, "INTENT_UNSUPPORTED_SYNTAX");
    assert.equal(stepPayload.diagnostics[0].syntax, "delegate reviewer");
    assert.equal(stepPayload.diagnostics[0].block, "step");
    assert.equal(stepPayload.diagnostics[0].span.start.line, 10);
    assert.equal(stepPayload.diagnostics[0].span.start.column, 7);

    assert.equal(verify.status, 1);
    assert.equal(verifyPayload.ok, false);
    assert.equal(verifyPayload.diagnostics[0].code, "INTENT_UNSUPPORTED_SYNTAX");
    assert.equal(verifyPayload.diagnostics[0].syntax, "ensure no_policy_violations");
    assert.equal(verifyPayload.diagnostics[0].block, "verify");
    assert.equal(verifyPayload.diagnostics[0].span.start.line, 13);
    assert.equal(verifyPayload.diagnostics[0].span.start.column, 5);

    assert.equal(invariant.status, 1);
    assert.equal(invariantPayload.ok, false);
    assert.equal(invariantPayload.diagnostics[0].code, "INTENT_UNSUPPORTED_SYNTAX");
    assert.equal(invariantPayload.diagnostics[0].syntax, "ensure no_policy_violations");
    assert.equal(invariantPayload.diagnostics[0].block, "invariant");
    assert.equal(invariantPayload.diagnostics[0].span.start.line, 17);
    assert.equal(invariantPayload.diagnostics[0].span.start.column, 5);
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
    const fileWrite = graph.nodes.find((node) => node.kind === "Effect" && node.data.args.path === "./src/app.ts");
    const shellCheck = graph.nodes.find((node) => node.kind === "Check" && node.data.effect?.args.command === "npm test");
    const fileWriteRequest = graph.edges.find((edge) => edge.kind === "requests" && edge.to === fileWrite?.id);
    const planEdge = graph.edges.find((edge) => edge.kind === "plans");
    const precedesEdge = graph.edges.find((edge) => edge.kind === "precedes");
    const typeDeclareEdge = graph.edges.find((edge) => edge.kind === "declares" && edge.from.startsWith("type:"));
    const memoryDeclareEdge = graph.edges.find((edge) => edge.kind === "declares" && edge.to.includes(":memory:"));
    const capabilityOwnerEdge = graph.edges.find((edge) => {
      return edge.kind === "authorizes"
        && edge.from.includes(":capability:")
        && graph.nodes.find((node) => node.id === edge.to)?.kind === "Goal";
    });
    const plannedGoal = graph.nodes.find((node) => node.id === planEdge?.from);
    const plannedStep = graph.nodes.find((node) => node.id === planEdge?.to);
    const previousStep = graph.nodes.find((node) => node.id === precedesEdge?.from);
    const nextStep = graph.nodes.find((node) => node.id === precedesEdge?.to);
    const declaredType = graph.nodes.find((node) => node.id === typeDeclareEdge?.from);
    const typeGoal = graph.nodes.find((node) => node.id === typeDeclareEdge?.to);
    const memoryGoal = graph.nodes.find((node) => node.id === memoryDeclareEdge?.from);
    const declaredMemory = graph.nodes.find((node) => node.id === memoryDeclareEdge?.to);
    const owningCapability = graph.nodes.find((node) => node.id === capabilityOwnerEdge?.from);
    const capabilityGoal = graph.nodes.find((node) => node.id === capabilityOwnerEdge?.to);

    assert.equal(graph.schema_version, "intent.graph.v0");
    assert.equal(graph.ok, true);
    assert.equal(kinds.has("Goal"), true);
    assert.equal(kinds.has("Type"), true);
    assert.equal(kinds.has("Capability"), true);
    assert.equal(kinds.has("Effect"), true);
    assert.equal(kinds.has("Step"), true);
    assert.equal(kinds.has("Check"), true);
    assert.equal(Boolean(fileWrite), true);
    assert.equal(fileWrite.data.argSpans.path.start.line, 39);
    assert.equal(fileWrite.data.argSpans.path.start.column, 24);
    assert.equal(Boolean(fileWriteRequest), true);
    assert.equal(fileWriteRequest.data.family, "file");
    assert.equal(fileWriteRequest.data.action, "write");
    assert.equal(fileWriteRequest.data.contractId, "intent.effect.file.write.v0");
    assert.deepEqual(fileWriteRequest.data.contractArguments, { path: "path" });
    assert.deepEqual(fileWriteRequest.data.args, fileWrite.data.args);
    assert.equal(fileWriteRequest.data.targetSpan.start.line, 39);
    assert.equal(graph.nodes.some((node) => node.kind === "Effect" && node.data.trust.zone === "trusted"), true);
    assert.equal(graph.nodes.some((node) => node.kind === "Memory" && node.data.retentionRules[0].subject.raw === "summaries"), true);
    assert.equal(Boolean(shellCheck), true);
    assert.equal(shellCheck.data.effect.argSpans.command.start.line, 49);
    assert.equal(shellCheck.data.effect.argSpans.command.start.column, 19);
    assert.equal(graph.nodes.some((node) => node.kind === "Capability" && node.data.grants.some((grant) => {
      return grant.value === "npm test" && grant.span?.start?.line === 27;
    })), true);
    assert.equal(Boolean(planEdge), true);
    assert.equal(planEdge.data.goal, plannedGoal.label);
    assert.equal(planEdge.data.step, plannedStep.label);
    assert.equal(planEdge.data.index, 0);
    assert.equal(planEdge.data.sourceSpan.start.line, plannedGoal.span.start.line);
    assert.equal(planEdge.data.targetSpan.start.line, plannedStep.span.start.line);
    assert.equal(Boolean(precedesEdge), true);
    assert.equal(precedesEdge.data.previousStep, previousStep.label);
    assert.equal(precedesEdge.data.nextStep, nextStep.label);
    assert.equal(precedesEdge.data.nextIndex, precedesEdge.data.previousIndex + 1);
    assert.equal(precedesEdge.data.sourceSpan.start.line, previousStep.span.start.line);
    assert.equal(precedesEdge.data.targetSpan.start.line, nextStep.span.start.line);
    assert.equal(Boolean(typeDeclareEdge), true);
    assert.equal(typeDeclareEdge.data.type, declaredType.label);
    assert.equal(typeDeclareEdge.data.goal, typeGoal.label);
    assert.equal(typeDeclareEdge.data.sourceSpan.start.line, declaredType.span.start.line);
    assert.equal(typeDeclareEdge.data.targetSpan.start.line, typeGoal.span.start.line);
    assert.equal(Boolean(memoryDeclareEdge), true);
    assert.equal(memoryDeclareEdge.data.goal, memoryGoal.label);
    assert.equal(memoryDeclareEdge.data.memory, declaredMemory.label);
    assert.equal(memoryDeclareEdge.data.memoryScope, declaredMemory.data.scope);
    assert.equal(memoryDeclareEdge.data.targetSpan.start.line, declaredMemory.span.start.line);
    assert.equal(Boolean(capabilityOwnerEdge), true);
    assert.equal(capabilityOwnerEdge.data.capability, owningCapability.label);
    assert.equal(capabilityOwnerEdge.data.family, owningCapability.data.family);
    assert.equal(capabilityOwnerEdge.data.approvalPolicy, owningCapability.data.approvalPolicy);
    assert.equal(capabilityOwnerEdge.data.goal, capabilityGoal.label);
    assert.equal(capabilityOwnerEdge.data.sourceSpan.start.line, owningCapability.span.start.line);
    assert.equal(graph.edges.some((edge) => edge.kind === "gates"), true);
    assert.equal(graph.edges.some((edge) => edge.kind === "authorizes" && edge.to.includes(":verify:")), true);
  });

  it("emits structured context sources with first-prototype trust metadata", () => {
    const graph = runJson(["graph", VALID_CONTEXT_TRUST_GRAPH]);
    const repoContext = graph.nodes.find((node) => node.kind === "Context" && node.data.source === "repo");
    const webContext = graph.nodes.find((node) => node.kind === "Context" && node.data.source === "web");
    const documentsContext = graph.nodes.find((node) => node.kind === "Context" && node.data.source === "documents");
    const webAuthorization = graph.edges.find((edge) => edge.kind === "authorizes" && edge.to === webContext.id);
    const documentsAuthorization = graph.edges.find((edge) => edge.kind === "authorizes" && edge.to === documentsContext.id);
    const webInform = graph.edges.find((edge) => edge.kind === "informs" && edge.from === webContext.id);

    assert.equal(graph.ok, true);
    assert.equal(repoContext.data.args._0, "./");
    assert.equal(repoContext.data.argKinds._0, "string");
    assert.equal(repoContext.data.argSpans._0.start.line, 28);
    assert.equal(repoContext.data.argSpans._0.start.column, 16);
    assert.equal(repoContext.data.expression, "repo(\"./\")");
    assert.equal(repoContext.data.trust.zone, "trusted");
    assert.equal(repoContext.data.trust.source, "local_context");
    assert.equal(repoContext.data.contractId, undefined);
    assert.equal(repoContext.data.contractArguments, undefined);
    assert.equal(webContext.data.args._0, "https://example.com/**");
    assert.equal(webContext.data.contractId, "intent.effect.web.read.v0");
    assert.deepEqual(webContext.data.contractArguments, { domain: "_0" });
    assert.equal(webContext.data.trust.zone, "untrusted");
    assert.equal(webContext.data.trust.source, "external_context");
    assert.equal(documentsContext.data.trust.zone, "trusted");
    assert.equal(documentsContext.data.contractId, "intent.effect.file.read.v0");
    assert.deepEqual(documentsContext.data.contractArguments, { path: "_0" });
    assert.equal(Boolean(webInform), true);
    assert.equal(webInform.data.source, "web");
    assert.equal(webInform.data.expression, webContext.data.expression);
    assert.deepEqual(webInform.data.args, webContext.data.args);
    assert.deepEqual(webInform.data.trust, webContext.data.trust);
    assert.equal(webInform.data.contractId, "intent.effect.web.read.v0");
    assert.deepEqual(webInform.data.contractArguments, { domain: "_0" });
    assert.equal(webInform.data.sourceSpan.start.line, webContext.span.start.line);
    assert.equal(Boolean(webAuthorization), true);
    assert.equal(webAuthorization.data.contractId, "intent.effect.web.read.v0");
    assert.deepEqual(webAuthorization.data.contractArguments, { domain: "_0" });
    assert.deepEqual(webAuthorization.data.grants.map((grant) => [grant.argument, grant.sourceArgument, grant.grantValue]), [
      ["domain", "_0", "example.com"],
    ]);
    assert.equal(Boolean(documentsAuthorization), true);
    assert.equal(documentsAuthorization.data.contractId, "intent.effect.file.read.v0");
    assert.deepEqual(documentsAuthorization.data.contractArguments, { path: "_0" });
    assert.deepEqual(documentsAuthorization.data.grants.map((grant) => [grant.argument, grant.sourceArgument, grant.grantValue]), [
      ["path", "_0", "./docs/**"],
    ]);
    assert.equal(graph.edges.some((edge) => edge.kind === "authorizes" && edge.to === repoContext.id), false);
  });

  it("emits explicit data dependencies and completion gates", () => {
    const graph = runJson(["graph", VALID_DEPENDENCY_GRAPH]);
    const kinds = new Set(graph.nodes.map((node) => node.kind));

    assert.equal(graph.ok, true);
    assert.equal(kinds.has("Input"), true);
    assert.equal(kinds.has("Completion"), true);
    assert.equal(graph.edges.some((edge) => {
      return edge.kind === "data"
        && edge.data.type === "GoalRequest"
        && edge.data.sourceSpan.start.line === 19
        && edge.data.sourceSpan.start.column === 30
        && edge.data.targetSpan.start.line === 37
        && edge.data.targetSpan.start.column === 22;
    }), true);
    assert.equal(graph.edges.some((edge) => {
      return edge.kind === "requires"
        && edge.data.type === "GoalRequest"
        && edge.data.targetSpan.start.line === 37
        && edge.data.targetSpan.start.column === 22;
    }), true);
    assert.equal(graph.nodes.some((node) => {
      return node.kind === "Goal"
        && node.data.outputType === "VerifiedPatch"
        && node.data.outputTypeSpan.start.line === 19
        && node.data.outputTypeSpan.start.column === 55;
    }), true);
    assert.equal(graph.nodes.some((node) => {
      return node.kind === "Input"
        && node.data.scope === "goal"
        && node.label === "request"
        && node.span.start.line === 19
        && node.span.start.column === 30;
    }), true);
    assert.equal(graph.edges.some((edge) => {
      return edge.kind === "supplies"
        && edge.from.endsWith(":input:request")
        && edge.to === "goal:apply_dependency_change"
        && edge.data.parameter === "request"
        && edge.data.type === "GoalRequest"
        && edge.data.sourceSpan.start.line === 19
        && edge.data.sourceSpan.start.column === 30
        && edge.data.targetSpan.start.line === 19
        && edge.data.targetSpan.start.column === 30;
    }), true);
    assert.equal(graph.nodes.some((node) => {
      return node.kind === "Input"
        && node.data.scope === "step"
        && node.label === "input"
        && node.span.start.line === 37
        && node.span.start.column === 22;
    }), true);
    assert.equal(graph.nodes.some((node) => {
      return node.kind === "Step"
        && node.label === "inspect_request"
        && node.data.outputType === "Finding"
        && node.data.outputTypeSpan.start.line === 37
        && node.data.outputTypeSpan.start.column === 45;
    }), true);
    assert.equal(graph.nodes.some((node) => {
      return node.kind === "Completion"
        && node.data.outputType === "VerifiedPatch"
        && node.data.outputTypeSpan.start.line === 19
        && node.data.outputTypeSpan.start.column === 55;
    }), true);
    assert.equal(graph.edges.some((edge) => {
      return edge.kind === "data"
        && edge.data.type === "Finding"
        && edge.data.sourceSpan.start.line === 37
        && edge.data.sourceSpan.start.column === 45
        && edge.data.targetSpan.start.line === 38
        && edge.data.targetSpan.start.column === 17;
    }), true);
    assert.equal(graph.edges.some((edge) => {
      return edge.kind === "data"
        && edge.data.type === "Patch"
        && edge.data.sourceSpan.start.line === 38
        && edge.data.sourceSpan.start.column === 36
        && edge.data.targetSpan.start.line === 41
        && edge.data.targetSpan.start.column === 19;
    }), true);
    assert.equal(graph.edges.some((edge) => edge.kind === "verifies" && edge.to.endsWith(":completion")), true);
    assert.equal(graph.edges.some((edge) => {
      return edge.kind === "gates"
        && edge.data.requirement === "shell(\"npm test\").exit_code == 0"
        && edge.data.scope === "goal"
        && edge.data.sourceSpan.start.line === 47
        && edge.data.sourceSpan.start.column === 5
        && edge.data.targetSpan.start.line === 19
        && edge.data.targetSpan.start.column === 1;
    }), true);
    assert.equal(graph.edges.some((edge) => {
      return edge.kind === "verifies"
        && edge.data.requirement === "shell(\"npm test\").exit_code == 0"
        && edge.data.scope === "goal"
        && edge.data.sourceSpan.start.line === 47
        && edge.data.targetSpan.start.line === 19;
    }), true);
    assert.equal(graph.edges.some((edge) => edge.kind === "guards" && edge.to.endsWith(":completion")), true);
    assert.equal(graph.edges.some((edge) => {
      return edge.kind === "produces"
        && edge.to.endsWith(":completion")
        && edge.data.type === "VerifiedPatch"
        && edge.data.sourceSpan.start.line === 41
        && edge.data.sourceSpan.start.column === 36
        && edge.data.targetSpan.start.line === 19
        && edge.data.targetSpan.start.column === 55;
    }), true);
  });

  it("keeps goal metadata aligned with owned inputs and completion", () => {
    for (const fixture of [VALID_CODE_CHANGE, VALID_DEPENDENCY_GRAPH, VALID_MEMORY_FLOW_GRAPH]) {
      const graph = runJson(["graph", fixture]);
      const goals = graph.nodes.filter((node) => node.kind === "Goal");

      assert.equal(graph.ok, true);
      for (const goal of goals) {
        assert.deepEqual(goal.data.parameters, attachedGoalValues(graph, goal, "parameters"));
        assert.deepEqual({
          outputType: goal.data.outputType,
          outputTypeSpan: goal.data.outputTypeSpan,
        }, attachedGoalValues(graph, goal, "outputType"));
      }
    }
  });

  it("emits step requirement checks as preconditions without completion verification edges", () => {
    const graph = runJson(["graph", VALID_STEP_REQUIREMENTS]);
    const stepRequirement = graph.nodes.find((node) => node.kind === "Check" && node.data.scope === "step");

    assert.equal(graph.ok, true);
    assert.equal(stepRequirement.data.ownerStep, "patch_code");
    assert.equal(stepRequirement.data.requirement, "input.summary != \"\"");
    assert.equal(graph.edges.some((edge) => edge.from === stepRequirement.id && edge.kind === "requires" && edge.to.endsWith(":step:patch_code")), true);
    assert.equal(graph.edges.some((edge) => {
      return edge.from === stepRequirement.id
        && edge.kind === "gates"
        && edge.to === "goal:apply_guarded_code_change"
        && edge.data.requirement === "input.summary != \"\""
        && edge.data.scope === "step"
        && edge.data.sourceSpan.start.line === 39
        && edge.data.targetSpan.start.line === 15;
    }), true);
    assert.equal(graph.edges.some((edge) => edge.from === stepRequirement.id && edge.kind === "verifies"), false);
  });

  it("emits step checkpoints as checkpoint nodes and edges", () => {
    const graph = runJson(["graph", VALID_CHECKPOINT_GRAPH]);
    const checkpoint = graph.nodes.find((node) => node.kind === "Checkpoint" && node.data.ownerStep === "patch_code");
    const patchStep = graph.nodes.find((node) => node.kind === "Step" && node.label === "patch_code");
    const completion = graph.nodes.find((node) => node.kind === "Completion");

    assert.equal(graph.ok, true);
    assert.equal(checkpoint.data.scope, "step");
    assert.equal(checkpoint.data.checkpoint, "before patch");
    assert.deepEqual(patchStep.data.checkpoints, ["before patch", "patch written"]);
    assert.equal(graph.edges.some((edge) => edge.kind === "checkpoints" && edge.from === patchStep.id && edge.to === checkpoint.id), true);
    assert.equal(graph.edges.some((edge) => edge.from === checkpoint.id && edge.kind === "verifies"), false);
    assert.equal(completion.data.checkpoint.required, true);
    assert.deepEqual(completion.data.checkpoint.requirements.map((record) => record.requirement), ["final_state_checkpointed"]);
    assert.deepEqual(completion.data.checkpoint.checkpoints.map((record) => [record.step, record.checkpoint]), [["verify_patch", "verification complete"]]);
  });

  it("emits invariant guards to completion, effects, checkpoints, policies, and step requirements", () => {
    const graph = runJson(["graph", VALID_STEP_POLICY_GRAPH]);
    const invariant = graph.nodes.find((node) => node.kind === "Invariant" && node.data.invariant === "secret_write");
    const effect = graph.nodes.find((node) => node.kind === "Effect" && node.data.family === "file");
    const checkpoint = graph.nodes.find((node) => node.kind === "Checkpoint" && node.data.ownerStep === "patch_code");
    const timeout = graph.nodes.find((node) => node.kind === "Policy" && node.data.policyKind === "timeout" && node.data.ownerStep === "patch_code");
    const retry = graph.nodes.find((node) => node.kind === "Policy" && node.data.policyKind === "retry" && node.data.ownerStep === "patch_code");
    const requirement = graph.nodes.find((node) => node.kind === "Check" && node.data.scope === "step");

    assert.equal(graph.ok, true);
    assert.equal(graph.edges.some((edge) => edge.kind === "guards" && edge.from === invariant.id && edge.to.endsWith(":completion")), true);
    assert.equal(graph.edges.some((edge) => edge.kind === "guards" && edge.from === invariant.id && edge.to === effect.id), true);
    assert.equal(graph.edges.some((edge) => edge.kind === "guards" && edge.from === invariant.id && edge.to === checkpoint.id), true);
    assert.equal(graph.edges.some((edge) => edge.kind === "guards" && edge.from === invariant.id && edge.to === timeout.id), true);
    assert.equal(graph.edges.some((edge) => edge.kind === "guards" && edge.from === invariant.id && edge.to === retry.id), true);
    assert.equal(graph.edges.some((edge) => edge.kind === "guards" && edge.from === invariant.id && edge.to === requirement.id), true);

    const requiredGraph = runJson(["graph", VALID_INVARIANT_GUARD_GRAPH]);
    const requireInvariant = requiredGraph.nodes.find((node) => node.kind === "Invariant" && node.data.assertion === "Require");
    assert.equal(requireInvariant.data.invariant, "reversible_operations_cited");
    assert.equal(requiredGraph.edges.some((edge) => edge.kind === "constrains" && edge.from === requireInvariant.id), true);
    assert.equal(requiredGraph.edges.some((edge) => edge.kind === "guards" && edge.from === requireInvariant.id && edge.to.endsWith(":completion")), true);
  });

  it("emits step approvals as approval nodes and edges", () => {
    const graph = runJson(["graph", VALID_STEP_APPROVAL_GRAPH]);
    const approval = graph.nodes.find((node) => node.kind === "Approval" && node.data.ownerStep === "publish_patch");
    const publishStep = graph.nodes.find((node) => node.kind === "Step" && node.label === "publish_patch");

    assert.equal(graph.ok, true);
    assert.equal(approval.data.scope, "step");
    assert.equal(approval.data.approval, "maintainer approves main push");
    assert.deepEqual(publishStep.data.approvals, ["maintainer approves main push"]);
    assert.equal(graph.nodes.some((node) => node.kind === "Capability" && node.data.family === "git" && node.data.approvalPolicy === "required"), true);
    assert.equal(graph.nodes.some((node) => node.kind === "Effect" && node.label === "GitPush" && node.data.approvalRequired), true);
    assert.equal(graph.edges.some((edge) => edge.kind === "approves" && edge.from === approval.id && edge.to === publishStep.id), true);
    assert.equal(graph.edges.some((edge) => edge.kind === "approves" && edge.from === approval.id && edge.to.includes(":effect:")), true);
    assert.equal(graph.edges.some((edge) => edge.from === approval.id && edge.kind === "verifies"), false);
  });

  it("emits secret reads as authorized secret effect nodes", () => {
    const graph = runJson(["graph", VALID_SECRET_READ]);
    const secretEffect = graph.nodes.find((node) => node.kind === "Effect" && node.label === "SecretRead");

    assert.equal(graph.ok, true);
    assert.equal(secretEffect.data.family, "secret");
    assert.equal(secretEffect.data.action, "read");
    assert.equal(secretEffect.data.args.name, "GITHUB_TOKEN");
    assert.equal(secretEffect.data.trust.zone, "trusted");
    assert.equal(graph.edges.some((edge) => edge.kind === "authorizes" && edge.to === secretEffect.id), true);
  });

  it("emits ticket updates as authorized ticket effect nodes", () => {
    const graph = runJson(["graph", VALID_TICKET_UPDATE]);
    const ticketEffect = graph.nodes.find((node) => node.kind === "Effect" && node.label === "TicketUpdate");

    assert.equal(graph.ok, true);
    assert.equal(ticketEffect.data.family, "ticket");
    assert.equal(ticketEffect.data.action, "update");
    assert.equal(ticketEffect.data.args.id, "CODE-123");
    assert.equal(graph.edges.some((edge) => edge.kind === "authorizes" && edge.to === ticketEffect.id), true);
  });

  it("emits deploys as authorized deploy effect nodes", () => {
    const graph = runJson(["graph", VALID_DEPLOY_TARGET]);
    const deployEffect = graph.nodes.find((node) => node.kind === "Effect" && node.label === "Deploy");

    assert.equal(graph.ok, true);
    assert.equal(deployEffect.data.family, "deploy");
    assert.equal(deployEffect.data.action, "deploy");
    assert.equal(deployEffect.data.args.target, "staging");
    assert.equal("risk" in deployEffect.data, false);
    assert.equal(graph.edges.some((edge) => edge.kind === "authorizes" && edge.to === deployEffect.id), true);
  });

  it("emits git commits as authorized git effect nodes", () => {
    const graph = runJson(["graph", VALID_GIT_COMMIT_MESSAGE]);
    const commitEffect = graph.nodes.find((node) => node.kind === "Effect" && node.label === "GitCommit");

    assert.equal(graph.ok, true);
    assert.equal(commitEffect.data.family, "git");
    assert.equal(commitEffect.data.action, "commit");
    assert.equal(commitEffect.data.args.message, "ship fix");
    assert.equal(graph.edges.some((edge) => edge.kind === "authorizes" && edge.to === commitEffect.id), true);
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
    assert.deepEqual(patchStep.data.timeouts, ["5m"]);
    assert.deepEqual(patchStep.data.retries, ["max 2"]);
    assert.equal(graph.edges.some((edge) => edge.kind === "timeouts" && edge.from === timeout.id && edge.to === patchStep.id), true);
    assert.equal(graph.edges.some((edge) => edge.kind === "retries" && edge.from === retry.id && edge.to === patchStep.id), true);
    assert.equal(graph.edges.some((edge) => edge.from === timeout.id && edge.kind === "verifies"), false);
  });

  it("keeps step summary metadata aligned with owned child nodes", () => {
    for (const fixture of [VALID_DEPENDENCY_GRAPH, VALID_STEP_POLICY_GRAPH, VALID_STEP_APPROVAL_GRAPH, VALID_CHECKPOINT_GRAPH, VALID_MEMORY_FLOW_GRAPH]) {
      const graph = runJson(["graph", fixture]);
      const steps = graph.nodes.filter((node) => node.kind === "Step");

      assert.equal(graph.ok, true);
      for (const step of steps) {
        for (const field of ["inputs", "effects", "requirements", "checkpoints", "approvals", "timeouts", "retries", "memoryAccesses"]) {
          assert.deepEqual(step.data[field], attachedStepValues(graph, step, field));
        }
      }
    }
  });

  it("emits memory access provenance edges", () => {
    const graph = runJson(["graph", VALID_MEMORY_FLOW_GRAPH]);
    const memory = graph.nodes.find((node) => node.kind === "Memory" && node.data.scope === "session");
    const completion = graph.nodes.find((node) => node.kind === "Completion");
    const inspectStep = graph.nodes.find((node) => node.kind === "Step" && node.label === "inspect");
    const draftStep = graph.nodes.find((node) => node.kind === "Step" && node.label === "draft");
    const writeEdge = graph.edges.find((edge) => edge.kind === "writes");
    const keyWriteEdge = graph.edges.find((edge) => edge.kind === "writes" && edge.data.key === "decisions");
    const readEdge = graph.edges.find((edge) => edge.kind === "reads");
    const citeEdge = graph.edges.find((edge) => edge.kind === "cites");

    assert.equal(graph.ok, true);
    assert.equal(memory.data.keys[0].name, "decisions");
    assert.equal(memory.data.keys[0].type, "Record");
    assert.deepEqual(inspectStep.data.memoryAccesses, ["session.evidence", "session.decisions"]);
    assert.deepEqual(draftStep.data.memoryAccesses, ["session.evidence", "session.evidence"]);
    assert.equal(completion.data.provenance.required, true);
    assert.deepEqual(completion.data.provenance.requirements.map((requirement) => requirement.requirement), ["memory_provenance_complete"]);
    assert.deepEqual(completion.data.provenance.citations.map((citation) => [citation.step, citation.target]), [["draft", "session.evidence"]]);
    assert.equal(writeEdge.from, inspectStep.id);
    assert.equal(writeEdge.to, memory.id);
    assert.equal(writeEdge.data.access, "write");
    assert.equal(writeEdge.data.target, "session.evidence");
    assert.equal(writeEdge.data.retentionRef, "retain evidence until 30d");
    assert.equal(keyWriteEdge.from, inspectStep.id);
    assert.equal(keyWriteEdge.to, memory.id);
    assert.equal(keyWriteEdge.data.retentionRef, null);
    assert.equal(readEdge.from, memory.id);
    assert.equal(readEdge.to, draftStep.id);
    assert.equal(readEdge.data.access, "read");
    assert.equal(readEdge.data.retentionRef, "retain evidence until 30d");
    assert.equal(citeEdge.from, memory.id);
    assert.equal(citeEdge.to, draftStep.id);
    assert.equal(citeEdge.data.access, "cite");
  });

  it("emits only graph edges whose endpoints exist in the same payload", () => {
    const validFixtures = [
      VALID_CODE_CHANGE,
      VALID_CHECKPOINT_GRAPH,
      VALID_CONTEXT_TRUST_GRAPH,
      VALID_DEPLOY_TARGET,
      VALID_DEPENDENCY_GRAPH,
      VALID_GIT_COMMIT_MESSAGE,
      VALID_GIT_PUSH_BRANCH,
      VALID_INVARIANT_GUARD_GRAPH,
      VALID_MEMORY_FLOW_GRAPH,
      VALID_RESEARCH,
      VALID_SECRET_READ,
      VALID_STEP_APPROVAL_GRAPH,
      VALID_STEP_POLICY_GRAPH,
      VALID_STEP_REQUIREMENTS,
      VALID_TICKET_UPDATE,
      VALID_TRUST_FLOW_SHELL_LITERAL,
      VALID_WEB_READ_WILDCARD,
    ];

    for (const fixture of validFixtures) {
      assertGraphEdgesResolve(runJson(["graph", fixture]));
    }
  });

  it("emits acyclic execution graphs", () => {
    const validFixtures = [
      VALID_CODE_CHANGE,
      VALID_CHECKPOINT_GRAPH,
      VALID_CONTEXT_TRUST_GRAPH,
      VALID_DEPLOY_TARGET,
      VALID_DEPENDENCY_GRAPH,
      VALID_GIT_COMMIT_MESSAGE,
      VALID_GIT_PUSH_BRANCH,
      VALID_INVARIANT_GUARD_GRAPH,
      VALID_MEMORY_FLOW_GRAPH,
      VALID_RESEARCH,
      VALID_SECRET_READ,
      VALID_STEP_APPROVAL_GRAPH,
      VALID_STEP_POLICY_GRAPH,
      VALID_STEP_REQUIREMENTS,
      VALID_TICKET_UPDATE,
      VALID_TRUST_FLOW_SHELL_LITERAL,
      VALID_WEB_READ_WILDCARD,
    ];

    for (const fixture of validFixtures) {
      assertGraphAcyclic(runJson(["graph", fixture]));
    }
  });

  it("validates graph endpoint and cycle diagnostics", () => {
    const danglingDiagnostics = validateTestGraph({
      source: "synthetic.intent",
      nodes: [{ id: "node:a", kind: "Type", label: "a", span: testSpan(1) }],
      edges: [{ from: "node:a", to: "node:missing", kind: "requests" }],
    });
    const cycleDiagnostics = validateTestGraph({
      source: "synthetic.intent",
      nodes: [
        { id: "goal:demo", kind: "Goal", label: "demo", span: testSpan(1) },
        { id: "goal:demo:step:a", kind: "Step", label: "a", span: testSpan(2) },
        { id: "goal:demo:step:b", kind: "Step", label: "b", span: testSpan(3) },
      ],
      edges: [
        { from: "goal:demo", to: "goal:demo:step:a", kind: "plans" },
        { from: "goal:demo", to: "goal:demo:step:b", kind: "plans" },
        { from: "goal:demo:step:a", to: "goal:demo:step:b", kind: "precedes" },
        { from: "goal:demo:step:b", to: "goal:demo:step:a", kind: "precedes" },
      ],
    });

    assert.equal(danglingDiagnostics[0].code, "INTENT_GRAPH_EDGE_UNRESOLVED");
    assert.equal(danglingDiagnostics[0].to, "node:missing");
    assert.deepEqual(danglingDiagnostics[0].missing_endpoints, ["to"]);
    const cycleDiagnostic = cycleDiagnostics.find((diagnostic) => diagnostic.code === "INTENT_GRAPH_CYCLE");
    assert.deepEqual(cycleDiagnostic.cycle, ["goal:demo", "goal:demo:step:a", "goal:demo:step:b", "goal:demo:step:a"]);
  });

  it("validates graph duplicate node diagnostics", () => {
    const diagnostics = validateTestGraph({
      source: "synthetic.intent",
      nodes: [
        { id: "node:a", kind: "Type", label: "a", span: testSpan(1) },
        { id: "node:a", kind: "Context", label: "a", span: testSpan(2) },
      ],
      edges: [],
    });

    assert.equal(diagnostics.length, 1);
    assert.equal(diagnostics[0].code, "INTENT_GRAPH_NODE_DUPLICATE");
    assert.equal(diagnostics[0].node_id, "node:a");
    assert.equal(diagnostics[0].node_kind, "Context");
    assert.equal(diagnostics[0].previous_node_kind, "Type");
    assert.equal(diagnostics[0].previous_span.start.line, 1);
    assert.equal(diagnostics[0].span.start.line, 2);
  });

  it("validates graph schema version diagnostics", () => {
    const diagnostics = validateGraph({
      schema_version: "intent.graph.v1",
      ast_schema_version: "intent.ast.v1",
      source: "synthetic.intent",
      package: "fixtures.synthetic",
      ok: true,
      diagnostics: [],
      nodes: [],
      edges: [],
    });
    const missingDiagnostics = validateGraph({
      source: "synthetic.intent",
      package: "fixtures.synthetic",
      ok: true,
      diagnostics: [],
      nodes: [],
      edges: [],
    });

    assert.equal(diagnostics.length, 1);
    assert.equal(diagnostics[0].code, "INTENT_GRAPH_SCHEMA_INVALID");
    assert.equal(diagnostics[0].schema_version, "intent.graph.v1");
    assert.equal(diagnostics[0].expected_schema_version, "intent.graph.v0");
    assert.equal(diagnostics[0].ast_schema_version, "intent.ast.v1");
    assert.equal(diagnostics[0].expected_ast_schema_version, "intent.ast.v0");
    assert.equal(missingDiagnostics.length, 1);
    assert.equal(missingDiagnostics[0].code, "INTENT_GRAPH_SCHEMA_INVALID");
    assert.equal(missingDiagnostics[0].schema_version, null);
    assert.equal(missingDiagnostics[0].ast_schema_version, null);
  });

  it("documents every emitted diagnostic code", () => {
    const emitted = emittedDiagnosticCodes();
    const documented = documentedDiagnosticCodes();
    const missing = emitted.filter((code) => !documented.includes(code));

    assert.deepEqual(missing, []);
    assert.equal(documented.includes("INTENT_GRAPH_ENVELOPE_UNSUPPORTED"), false);
  });

  it("validates graph envelope provenance diagnostics", () => {
    const diagnostics = validateGraph({
      schema_version: "intent.graph.v0",
      ast_schema_version: "intent.ast.v0",
      source: 1,
      package: null,
      ok: true,
      diagnostics: [],
      nodes: [],
      edges: [],
    });
    const blankDiagnostics = validateGraph({
      schema_version: "intent.graph.v0",
      ast_schema_version: "intent.ast.v0",
      source: "   ",
      package: "",
      ok: true,
      diagnostics: [],
      nodes: [],
      edges: [],
    });

    assert.equal(diagnostics.length, 1);
    assert.equal(diagnostics[0].code, "INTENT_GRAPH_ENVELOPE_INVALID");
    assert.equal(diagnostics[0].source_is_string, false);
    assert.equal(diagnostics[0].package_is_string, false);
    assert.equal(diagnostics[0].source_is_nonempty, false);
    assert.equal(diagnostics[0].package_is_nonempty, false);
    assert.equal(diagnostics[0].source, null);
    assert.equal(diagnostics[0].package, null);
    assert.equal(blankDiagnostics.length, 1);
    assert.equal(blankDiagnostics[0].code, "INTENT_GRAPH_ENVELOPE_INVALID");
    assert.equal(blankDiagnostics[0].source_is_string, true);
    assert.equal(blankDiagnostics[0].package_is_string, true);
    assert.equal(blankDiagnostics[0].source_is_nonempty, false);
    assert.equal(blankDiagnostics[0].package_is_nonempty, false);
    assert.equal(blankDiagnostics[0].source, "   ");
    assert.equal(blankDiagnostics[0].package, "");
  });

  it("validates graph executable envelope diagnostics", () => {
    const failedDiagnostics = validateGraph({
      schema_version: "intent.graph.v0",
      ast_schema_version: "intent.ast.v0",
      source: "synthetic.intent",
      package: "fixtures.synthetic",
      ok: false,
      diagnostics: [{ code: "INTENT_VERIFY_MISSING", severity: "error", message: "missing", span: testSpan(1) }],
      nodes: [],
      edges: [],
    });
    const staleDiagnostics = validateGraph({
      schema_version: "intent.graph.v0",
      ast_schema_version: "intent.ast.v0",
      source: "synthetic.intent",
      package: "fixtures.synthetic",
      ok: true,
      diagnostics: [{ code: "INTENT_VERIFY_MISSING", severity: "error", message: "missing", span: testSpan(1) }],
      nodes: [],
      edges: [],
    });
    const malformedDiagnostics = validateGraph({
      schema_version: "intent.graph.v0",
      ast_schema_version: "intent.ast.v0",
      source: "synthetic.intent",
      package: "fixtures.synthetic",
      ok: true,
      nodes: [],
      edges: [],
    });

    assert.equal(failedDiagnostics.length, 1);
    assert.equal(failedDiagnostics[0].code, "INTENT_GRAPH_EXECUTABLE_INVALID");
    assert.equal(failedDiagnostics[0].graph_ok, false);
    assert.equal(failedDiagnostics[0].diagnostics_is_array, true);
    assert.equal(failedDiagnostics[0].diagnostic_count, 1);
    assert.equal(staleDiagnostics[0].code, "INTENT_GRAPH_EXECUTABLE_INVALID");
    assert.equal(staleDiagnostics[0].graph_ok, true);
    assert.equal(staleDiagnostics[0].diagnostic_count, 1);
    assert.equal(malformedDiagnostics[0].code, "INTENT_GRAPH_EXECUTABLE_INVALID");
    assert.equal(malformedDiagnostics[0].diagnostics_is_array, false);
    assert.equal(malformedDiagnostics[0].diagnostic_count, null);
  });

  it("validates graph diagnostic record diagnostics", () => {
    const missingDiagnosticsArray = validateGraph({
      schema_version: "intent.graph.v0",
      ast_schema_version: "intent.ast.v0",
      source: "synthetic.intent",
      package: "fixtures.synthetic",
      ok: false,
      diagnostics: "bad",
      nodes: [],
      edges: [],
    }, { allowNonExecutableEnvelope: true });
    const malformedDiagnostic = validateGraph({
      schema_version: "intent.graph.v0",
      ast_schema_version: "intent.ast.v0",
      source: "synthetic.intent",
      package: "fixtures.synthetic",
      ok: false,
      diagnostics: [
        { severity: "warning", code: "", message: "", span: { file: "synthetic.intent", start: { line: 0, column: 1 }, end: { line: 1, column: 1 } } },
      ],
      nodes: [],
      edges: [],
    }, { allowNonExecutableEnvelope: true });

    assert.equal(missingDiagnosticsArray.length, 1);
    assert.equal(missingDiagnosticsArray[0].code, "INTENT_GRAPH_DIAGNOSTIC_INVALID");
    assert.equal(missingDiagnosticsArray[0].diagnostics_is_array, false);
    assert.equal(malformedDiagnostic.length, 1);
    assert.equal(malformedDiagnostic[0].code, "INTENT_GRAPH_DIAGNOSTIC_INVALID");
    assert.equal(malformedDiagnostic[0].diagnostics_is_array, true);
    assert.equal(malformedDiagnostic[0].diagnostic_index, 0);
    assert.equal(malformedDiagnostic[0].severity_is_error, false);
    assert.equal(malformedDiagnostic[0].code_is_nonempty, false);
    assert.equal(malformedDiagnostic[0].message_is_nonempty, false);
    assert.equal(malformedDiagnostic[0].span_is_valid, false);
    assert.equal(malformedDiagnostic[0].span.file, "synthetic.intent");
    assert.equal(malformedDiagnostic[0].span.start.line, 1);
  });

  it("validates graph collection shape diagnostics", () => {
    const missingDiagnostics = validateGraph({
      schema_version: "intent.graph.v0",
      ast_schema_version: "intent.ast.v0",
      source: "synthetic.intent",
      package: "fixtures.synthetic",
      ok: true,
      diagnostics: [],
    });
    const malformedDiagnostics = validateGraph({
      schema_version: "intent.graph.v0",
      ast_schema_version: "intent.ast.v0",
      source: "synthetic.intent",
      package: "fixtures.synthetic",
      ok: true,
      diagnostics: [],
      nodes: {},
      edges: "bad",
    });

    assert.equal(missingDiagnostics.length, 1);
    assert.equal(missingDiagnostics[0].code, "INTENT_GRAPH_SHAPE_INVALID");
    assert.equal(missingDiagnostics[0].nodes_is_array, false);
    assert.equal(missingDiagnostics[0].edges_is_array, false);
    assert.equal(malformedDiagnostics.length, 1);
    assert.equal(malformedDiagnostics[0].code, "INTENT_GRAPH_SHAPE_INVALID");
    assert.equal(malformedDiagnostics[0].nodes_is_array, false);
    assert.equal(malformedDiagnostics[0].edges_is_array, false);
  });

  it("validates graph node and edge record diagnostics", () => {
    const diagnostics = validateGraph({
      schema_version: "intent.graph.v0",
      ast_schema_version: "intent.ast.v0",
      source: "synthetic.intent",
      package: "fixtures.synthetic",
      ok: true,
      diagnostics: [],
      nodes: [
        "bad",
        { id: "node:missing-kind", label: "bad", span: testSpan(2), data: {} },
        { id: "node:missing-payload", kind: "Type", span: testSpan(3) },
        { id: "node:bad-span", kind: "Type", label: "bad span", span: { file: "synthetic.intent", start: { line: 0, column: 1 }, end: { line: 1, column: 1 } }, data: {} },
        { id: "   ", kind: "Type", label: "blank", span: testSpan(5), data: {} },
        { id: "node:a", kind: "Type", label: "a", span: testSpan(6), data: { definition: null } },
      ],
      edges: [
        "bad",
        { from: "node:a", to: 1, kind: "requests" },
        { from: "node:a", to: "   ", kind: "requests" },
      ],
    });

    assert.equal(diagnostics.length, 8);
    assert.equal(diagnostics[0].code, "INTENT_GRAPH_NODE_INVALID");
    assert.equal(diagnostics[0].node_index, 0);
    assert.equal(diagnostics[0].node_id, null);
    assert.equal(diagnostics[0].node_kind, null);
    assert.equal(diagnostics[1].code, "INTENT_GRAPH_NODE_INVALID");
    assert.equal(diagnostics[1].node_index, 1);
    assert.equal(diagnostics[1].node_id, "node:missing-kind");
    assert.equal(diagnostics[1].node_kind, null);
    assert.equal(diagnostics[1].label_is_string, true);
    assert.equal(diagnostics[1].span_is_valid, true);
    assert.equal(diagnostics[1].data_is_object, true);
    assert.equal(diagnostics[2].code, "INTENT_GRAPH_NODE_INVALID");
    assert.equal(diagnostics[2].node_index, 2);
    assert.equal(diagnostics[2].node_id, "node:missing-payload");
    assert.equal(diagnostics[2].node_kind, "Type");
    assert.equal(diagnostics[2].label_is_string, false);
    assert.equal(diagnostics[2].span_is_valid, true);
    assert.equal(diagnostics[2].data_is_object, false);
    assert.equal(diagnostics[3].code, "INTENT_GRAPH_NODE_INVALID");
    assert.equal(diagnostics[3].node_index, 3);
    assert.equal(diagnostics[3].node_id, "node:bad-span");
    assert.equal(diagnostics[3].span_is_valid, false);
    assert.equal(diagnostics[4].code, "INTENT_GRAPH_NODE_INVALID");
    assert.equal(diagnostics[4].node_index, 4);
    assert.equal(diagnostics[4].node_id, "   ");
    assert.equal(diagnostics[4].id_is_nonempty, false);
    assert.equal(diagnostics[4].kind_is_nonempty, true);
    assert.equal(diagnostics[4].label_is_nonempty, true);
    assert.equal(diagnostics[5].code, "INTENT_GRAPH_EDGE_INVALID");
    assert.equal(diagnostics[5].edge_index, 0);
    assert.equal(diagnostics[5].edge, null);
    assert.equal(diagnostics[5].from, null);
    assert.equal(diagnostics[5].to, null);
    assert.equal(diagnostics[6].code, "INTENT_GRAPH_EDGE_INVALID");
    assert.equal(diagnostics[6].edge_index, 1);
    assert.equal(diagnostics[6].edge, "requests");
    assert.equal(diagnostics[6].from, "node:a");
    assert.equal(diagnostics[6].to, 1);
    assert.equal(diagnostics[7].code, "INTENT_GRAPH_EDGE_INVALID");
    assert.equal(diagnostics[7].edge_index, 2);
    assert.equal(diagnostics[7].to_is_nonempty, false);
    assert.equal(diagnostics[7].from_is_nonempty, true);
    assert.equal(diagnostics[7].kind_is_nonempty, true);
  });

  it("validates malformed graph records without throwing", () => {
    const diagnostics = validateGraph({
      schema_version: "intent.graph.v0",
      ast_schema_version: "intent.ast.v0",
      source: "synthetic.intent",
      package: "fixtures.synthetic",
      ok: true,
      diagnostics: [],
      nodes: [
        null,
        { id: "node:a", kind: "Type", label: "a", span: testSpan(2), data: { definition: null } },
      ],
      edges: [
        null,
      ],
    });

    assert.equal(diagnostics.length, 2);
    assert.equal(diagnostics[0].code, "INTENT_GRAPH_NODE_INVALID");
    assert.equal(diagnostics[0].node_index, 0);
    assert.equal(diagnostics[0].node_id, null);
    assert.equal(diagnostics[0].node_kind, null);
    assert.equal(diagnostics[1].code, "INTENT_GRAPH_EDGE_INVALID");
    assert.equal(diagnostics[1].edge_index, 0);
    assert.equal(diagnostics[1].edge, null);
    assert.equal(diagnostics[1].from, null);
    assert.equal(diagnostics[1].to, null);
  });

  it("validates graph edge payload diagnostics", () => {
    const diagnostics = validateTestGraph({
      nodes: [
        { id: "node:a", kind: "Type", label: "a", span: testSpan(1), data: {} },
        { id: "node:b", kind: "Type", label: "b", span: testSpan(2), data: {} },
        { id: "node:c", kind: "Type", label: "c", span: testSpan(3), data: {} },
        { id: "node:d", kind: "Type", label: "d", span: testSpan(4), data: {} },
      ],
      edges: [
        { from: "node:a", to: "node:b", kind: "declares", data: "bad" },
        { from: "node:b", to: "node:c", kind: "declares", data: { sourceSpan: { file: "synthetic.intent", start: { line: 0, column: 1 }, end: { line: 1, column: 1 } } } },
        { from: "node:c", to: "node:d", kind: "declares", data: { targetSpan: { file: "synthetic.intent", start: { line: 1, column: 1 }, end: { line: 1, column: 0 } } } },
      ],
    });

    assert.equal(diagnostics.length, 3);
    assert.equal(diagnostics[0].code, "INTENT_GRAPH_EDGE_PAYLOAD_INVALID");
    assert.equal(diagnostics[0].edge_index, 0);
    assert.equal(diagnostics[0].data_is_object, false);
    assert.equal(diagnostics[0].source_span_is_valid, true);
    assert.equal(diagnostics[0].target_span_is_valid, true);
    assert.equal(diagnostics[1].code, "INTENT_GRAPH_EDGE_PAYLOAD_INVALID");
    assert.equal(diagnostics[1].edge_index, 1);
    assert.equal(diagnostics[1].data_is_object, true);
    assert.equal(diagnostics[1].source_span_is_valid, false);
    assert.equal(diagnostics[1].target_span_is_valid, true);
    assert.equal(diagnostics[2].code, "INTENT_GRAPH_EDGE_PAYLOAD_INVALID");
    assert.equal(diagnostics[2].edge_index, 2);
    assert.equal(diagnostics[2].source_span_is_valid, true);
    assert.equal(diagnostics[2].target_span_is_valid, false);
  });

  it("validates graph node kind diagnostics", () => {
    const diagnostics = validateTestGraph({
      source: "synthetic.intent",
      nodes: [
        { id: "node:widget", kind: "Widget", label: "widget", span: testSpan(1) },
      ],
      edges: [],
    });

    assert.equal(diagnostics.length, 1);
    assert.equal(diagnostics[0].code, "INTENT_GRAPH_NODE_KIND_INVALID");
    assert.equal(diagnostics[0].node_id, "node:widget");
    assert.equal(diagnostics[0].node_kind, "Widget");
    assert.equal(diagnostics[0].supported_node_kinds.includes("Goal"), true);
  });

  it("validates graph edge kind diagnostics", () => {
    const diagnostics = validateTestGraph({
      source: "synthetic.intent",
      nodes: [
        { id: "node:a", kind: "Type", label: "a", span: testSpan(1) },
        { id: "node:b", kind: "Type", label: "b", span: testSpan(2) },
      ],
      edges: [
        { from: "node:a", to: "node:b", kind: "teleports" },
      ],
    });

    assert.equal(diagnostics.length, 1);
    assert.equal(diagnostics[0].code, "INTENT_GRAPH_EDGE_KIND_INVALID");
    assert.equal(diagnostics[0].edge, "teleports");
    assert.equal(diagnostics[0].from, "node:a");
    assert.equal(diagnostics[0].to, "node:b");
    assert.equal(diagnostics[0].supported_edge_kinds.includes("requests"), true);
  });

  it("validates graph declares edge role diagnostics", () => {
    const diagnostics = validateTestGraph({
      source: "synthetic.intent",
      nodes: [
        { id: "goal:demo", kind: "Goal", label: "demo", span: testSpan(1) },
        { id: "goal:other", kind: "Goal", label: "other", span: testSpan(2) },
        { id: "type:Finding", kind: "Type", label: "Finding", span: testSpan(3) },
        { id: "goal:demo:memory:0", kind: "Memory", label: "memory", span: testSpan(4) },
      ],
      edges: [
        { from: "type:Finding", to: "goal:demo", kind: "declares" },
        { from: "type:Finding", to: "goal:other", kind: "declares" },
        { from: "goal:demo", to: "goal:demo:memory:0", kind: "declares" },
        { from: "type:Finding", to: "goal:demo:memory:0", kind: "declares" },
        { from: "goal:demo", to: "goal:other", kind: "declares" },
        { from: "goal:demo:memory:0", to: "goal:demo", kind: "declares" },
      ],
    }).filter((diagnostic) => diagnostic.code === "INTENT_GRAPH_DECLARE_INVALID");

    assert.equal(diagnostics.length, 3);
    assert.equal(diagnostics[0].from_kind, "Type");
    assert.equal(diagnostics[0].to_kind, "Memory");
    assert.equal(diagnostics[1].from_kind, "Goal");
    assert.equal(diagnostics[1].to_kind, "Goal");
    assert.equal(diagnostics[2].from_kind, "Memory");
    assert.equal(diagnostics[2].to_kind, "Goal");
    assert.deepEqual(diagnostics[2].supported_roles, [
      { from_kind: "Type", to_kind: "Goal" },
      { from_kind: "Goal", to_kind: "Memory" },
    ]);
  });

  it("validates graph authorizes edge role diagnostics", () => {
    const diagnostics = validateTestGraph({
      source: "synthetic.intent",
      nodes: [
        { id: "goal:demo", kind: "Goal", label: "demo", span: testSpan(1) },
        { id: "goal:other", kind: "Goal", label: "other", span: testSpan(2) },
        { id: "goal:demo:capability:0", kind: "Capability", label: "file", span: testSpan(3) },
        { id: "goal:demo:step:patch:effect:0", kind: "Effect", label: "FileWrite", span: testSpan(4) },
        { id: "goal:demo:verify:0", kind: "Check", label: "ok", span: testSpan(5), data: { effect: { family: "shell", action: "run" } } },
        { id: "goal:demo:context:0", kind: "Context", label: "web", span: testSpan(6), data: { source: "web" } },
        { id: "goal:demo:memory:0", kind: "Memory", label: "memory", span: testSpan(7) },
      ],
      edges: [
        { from: "goal:demo:capability:0", to: "goal:demo", kind: "authorizes" },
        { from: "goal:demo:capability:0", to: "goal:demo:step:patch:effect:0", kind: "authorizes" },
        { from: "goal:demo:capability:0", to: "goal:demo:verify:0", kind: "authorizes" },
        { from: "goal:demo:capability:0", to: "goal:demo:context:0", kind: "authorizes" },
        { from: "goal:demo", to: "goal:demo:step:patch:effect:0", kind: "authorizes" },
        { from: "goal:demo", to: "goal:demo:verify:0", kind: "authorizes" },
        { from: "goal:demo", to: "goal:demo:context:0", kind: "authorizes" },
        { from: "goal:demo", to: "goal:other", kind: "authorizes" },
        { from: "goal:demo:capability:0", to: "goal:demo:memory:0", kind: "authorizes" },
      ],
    }).filter((diagnostic) => diagnostic.code === "INTENT_GRAPH_AUTHORIZE_INVALID");

    assert.equal(diagnostics.length, 5);
    assert.equal(diagnostics[0].from_kind, "Goal");
    assert.equal(diagnostics[0].to_kind, "Effect");
    assert.equal(diagnostics[1].from_kind, "Goal");
    assert.equal(diagnostics[1].to_kind, "Check");
    assert.equal(diagnostics[2].from_kind, "Goal");
    assert.equal(diagnostics[2].to_kind, "Context");
    assert.equal(diagnostics[3].from_kind, "Goal");
    assert.equal(diagnostics[3].to_kind, "Goal");
    assert.equal(diagnostics[4].from_kind, "Capability");
    assert.equal(diagnostics[4].to_kind, "Memory");
    assert.deepEqual(diagnostics[4].supported_roles, [
      { from_kind: "Capability", to_kind: "Goal" },
      { from_kind: "Capability", to_kind: "Effect" },
      { from_kind: "Capability", to_kind: "Check" },
      { from_kind: "Capability", to_kind: "Context" },
    ]);
  });

  it("validates graph requests edge role diagnostics", () => {
    const diagnostics = validateTestGraph({
      source: "synthetic.intent",
      nodes: [
        { id: "goal:demo", kind: "Goal", label: "demo", span: testSpan(1) },
        { id: "goal:demo:step:patch", kind: "Step", label: "patch", span: testSpan(2), data: { effects: ["FileWrite"], requirements: ["synthetic"], checkpoints: ["before patch"], timeouts: ["5m"], retries: ["5m"] } },
        { id: "goal:demo:step:patch:effect:0", kind: "Effect", label: "FileWrite", span: testSpan(3) },
        { id: "goal:demo:verify:0", kind: "Check", label: "ok", span: testSpan(4) },
        { id: "goal:demo:context:0", kind: "Context", label: "repo", span: testSpan(5) },
      ],
      edges: [
        { from: "goal:demo:step:patch", to: "goal:demo:step:patch:effect:0", kind: "requests" },
        { from: "goal:demo:step:patch", to: "goal:demo", kind: "requests" },
        { from: "goal:demo:step:patch", to: "goal:demo:verify:0", kind: "requests" },
        { from: "goal:demo", to: "goal:demo:context:0", kind: "requests" },
      ],
    }).filter((diagnostic) => diagnostic.code === "INTENT_GRAPH_REQUEST_INVALID");

    assert.equal(diagnostics.length, 3);
    assert.equal(diagnostics[0].from_kind, "Step");
    assert.equal(diagnostics[0].to_kind, "Goal");
    assert.equal(diagnostics[1].from_kind, "Step");
    assert.equal(diagnostics[1].to_kind, "Check");
    assert.equal(diagnostics[2].from_kind, "Goal");
    assert.equal(diagnostics[2].to_kind, "Context");
    assert.deepEqual(diagnostics[2].supported_roles, [
      { to_kind: "Effect" },
    ]);
  });

  it("validates graph gate and verify edge role diagnostics", () => {
    const diagnostics = validateTestGraph({
      source: "synthetic.intent",
      nodes: [
        { id: "goal:demo", kind: "Goal", label: "demo", span: testSpan(1) },
        { id: "goal:demo:verify:0", kind: "Check", label: "ok", span: testSpan(2) },
        { id: "goal:demo:completion", kind: "Completion", label: "demo", span: testSpan(3) },
        { id: "goal:demo:step:patch", kind: "Step", label: "patch", span: testSpan(4) },
        { id: "goal:demo:context:0", kind: "Context", label: "repo", span: testSpan(5) },
      ],
      edges: [
        { from: "goal:demo:verify:0", to: "goal:demo", kind: "gates" },
        { from: "goal:demo:verify:0", to: "goal:demo:completion", kind: "verifies" },
        { from: "goal:demo:step:patch", to: "goal:demo", kind: "gates" },
        { from: "goal:demo:verify:0", to: "goal:demo:context:0", kind: "gates" },
        { from: "goal:demo", to: "goal:demo:completion", kind: "verifies" },
        { from: "goal:demo:verify:0", to: "goal:demo", kind: "verifies" },
      ],
    });
    const gateDiagnostics = diagnostics.filter((diagnostic) => diagnostic.code === "INTENT_GRAPH_GATE_INVALID");
    const verifyDiagnostics = diagnostics.filter((diagnostic) => diagnostic.code === "INTENT_GRAPH_VERIFY_INVALID");

    assert.equal(gateDiagnostics.length, 2);
    assert.equal(gateDiagnostics[0].from_kind, "Step");
    assert.equal(gateDiagnostics[0].to_kind, "Goal");
    assert.equal(gateDiagnostics[1].from_kind, "Check");
    assert.equal(gateDiagnostics[1].to_kind, "Context");
    assert.deepEqual(gateDiagnostics[1].supported_roles, [
      { from_kind: "Check", to_kind: "Goal" },
    ]);
    assert.equal(verifyDiagnostics.length, 2);
    assert.equal(verifyDiagnostics[0].from_kind, "Goal");
    assert.equal(verifyDiagnostics[0].to_kind, "Completion");
    assert.equal(verifyDiagnostics[1].from_kind, "Check");
    assert.equal(verifyDiagnostics[1].to_kind, "Goal");
    assert.deepEqual(verifyDiagnostics[1].supported_roles, [
      { from_kind: "Check", to_kind: "Completion" },
    ]);
  });

  it("validates graph plan edge role diagnostics", () => {
    const diagnostics = validateTestGraph({
      source: "synthetic.intent",
      nodes: [
        { id: "goal:demo", kind: "Goal", label: "demo", span: testSpan(1) },
        { id: "goal:demo:step:patch", kind: "Step", label: "patch", span: testSpan(2), data: { effects: ["FileWrite"] } },
        { id: "goal:demo:completion", kind: "Completion", label: "demo", span: testSpan(3) },
        { id: "goal:demo:context:0", kind: "Context", label: "repo", span: testSpan(4) },
      ],
      edges: [
        { from: "goal:demo", to: "goal:demo:step:patch", kind: "plans" },
        { from: "goal:demo:step:patch", to: "goal:demo", kind: "plans" },
        { from: "goal:demo", to: "goal:demo:completion", kind: "plans" },
        { from: "goal:demo:context:0", to: "goal:demo:step:patch", kind: "plans" },
      ],
    }).filter((diagnostic) => diagnostic.code === "INTENT_GRAPH_PLAN_INVALID");

    assert.equal(diagnostics.length, 3);
    assert.equal(diagnostics[0].from_kind, "Step");
    assert.equal(diagnostics[0].to_kind, "Goal");
    assert.equal(diagnostics[1].from_kind, "Goal");
    assert.equal(diagnostics[1].to_kind, "Completion");
    assert.equal(diagnostics[2].from_kind, "Context");
    assert.equal(diagnostics[2].to_kind, "Step");
    assert.deepEqual(diagnostics[2].supported_roles, [
      { from_kind: "Goal", to_kind: "Step" },
    ]);
  });

  it("validates graph completion delivery edge role diagnostics", () => {
    const diagnostics = validateTestGraph({
      source: "synthetic.intent",
      nodes: [
        { id: "goal:demo", kind: "Goal", label: "demo", span: testSpan(1) },
        { id: "goal:demo:step:patch", kind: "Step", label: "patch", span: testSpan(2), data: { effects: ["FileWrite"], requirements: ["synthetic"], checkpoints: ["before patch"], timeouts: ["5m"], retries: ["5m"] } },
        { id: "goal:demo:completion", kind: "Completion", label: "demo", span: testSpan(3) },
        { id: "goal:demo:context:0", kind: "Context", label: "repo", span: testSpan(4) },
      ],
      edges: [
        { from: "goal:demo", to: "goal:demo:completion", kind: "completes" },
        { from: "goal:demo:step:patch", to: "goal:demo:completion", kind: "produces", data: { type: "Report", sourceSpan: testSpan(2), targetSpan: testSpan(3) } },
        { from: "goal:demo:step:patch", to: "goal:demo:completion", kind: "completes" },
        { from: "goal:demo", to: "goal:demo:step:patch", kind: "completes" },
        { from: "goal:demo", to: "goal:demo:completion", kind: "produces", data: { type: "Report", sourceSpan: testSpan(1), targetSpan: testSpan(3) } },
        { from: "goal:demo:step:patch", to: "goal:demo:context:0", kind: "produces", data: { type: "Report", sourceSpan: testSpan(2), targetSpan: testSpan(4) } },
      ],
    });
    const completeDiagnostics = diagnostics.filter((diagnostic) => diagnostic.code === "INTENT_GRAPH_COMPLETE_INVALID");
    const produceDiagnostics = diagnostics.filter((diagnostic) => diagnostic.code === "INTENT_GRAPH_PRODUCE_INVALID");

    assert.equal(completeDiagnostics.length, 2);
    assert.equal(completeDiagnostics[0].from_kind, "Step");
    assert.equal(completeDiagnostics[0].to_kind, "Completion");
    assert.equal(completeDiagnostics[1].from_kind, "Goal");
    assert.equal(completeDiagnostics[1].to_kind, "Step");
    assert.deepEqual(completeDiagnostics[1].supported_roles, [
      { from_kind: "Goal", to_kind: "Completion" },
    ]);
    assert.equal(produceDiagnostics.length, 2);
    assert.equal(produceDiagnostics[0].from_kind, "Goal");
    assert.equal(produceDiagnostics[0].to_kind, "Completion");
    assert.equal(produceDiagnostics[1].from_kind, "Step");
    assert.equal(produceDiagnostics[1].to_kind, "Context");
    assert.deepEqual(produceDiagnostics[1].supported_roles, [
      { from_kind: "Step", to_kind: "Completion" },
    ]);
  });

  it("validates graph invariant edge role diagnostics", () => {
    const diagnostics = validateTestGraph({
      source: "synthetic.intent",
      nodes: [
        { id: "goal:demo", kind: "Goal", label: "demo", span: testSpan(1) },
        { id: "goal:demo:step:patch", kind: "Step", label: "patch", span: testSpan(2), data: { effects: ["FileWrite"] } },
        { id: "goal:demo:completion", kind: "Completion", label: "demo", span: testSpan(3) },
        { id: "goal:demo:invariant:0", kind: "Invariant", label: "rule", span: testSpan(4) },
        { id: "goal:demo:step:patch:effect:0", kind: "Effect", label: "FileWrite", span: testSpan(5) },
        { id: "goal:demo:step:patch:checkpoint:0", kind: "Checkpoint", label: "before", span: testSpan(6) },
        { id: "goal:demo:step:patch:timeout:0", kind: "Policy", label: "5m", span: testSpan(7) },
        { id: "goal:demo:step:patch:requirement:0", kind: "Check", label: "input.ready", span: testSpan(8), data: { scope: "step" } },
        { id: "goal:demo:verify:0", kind: "Check", label: "ok", span: testSpan(9), data: { scope: "goal" } },
      ],
      edges: [
        { from: "goal:demo:invariant:0", to: "goal:demo", kind: "constrains" },
        { from: "goal:demo:invariant:0", to: "goal:demo:completion", kind: "guards" },
        { from: "goal:demo:invariant:0", to: "goal:demo:step:patch:effect:0", kind: "guards" },
        { from: "goal:demo:invariant:0", to: "goal:demo:step:patch:checkpoint:0", kind: "guards" },
        { from: "goal:demo:invariant:0", to: "goal:demo:step:patch:timeout:0", kind: "guards" },
        { from: "goal:demo:invariant:0", to: "goal:demo:step:patch:requirement:0", kind: "guards" },
        { from: "goal:demo:step:patch", to: "goal:demo", kind: "constrains" },
        { from: "goal:demo:invariant:0", to: "goal:demo:completion", kind: "constrains" },
        { from: "goal:demo", to: "goal:demo:completion", kind: "guards" },
        { from: "goal:demo:invariant:0", to: "goal:demo", kind: "guards" },
        { from: "goal:demo:invariant:0", to: "goal:demo:verify:0", kind: "guards" },
      ],
    });
    const constrainDiagnostics = diagnostics.filter((diagnostic) => diagnostic.code === "INTENT_GRAPH_CONSTRAIN_INVALID");
    const guardRoleDiagnostics = diagnostics.filter((diagnostic) => diagnostic.code === "INTENT_GRAPH_GUARD_ROLE_INVALID");

    assert.equal(constrainDiagnostics.length, 2);
    assert.equal(constrainDiagnostics[0].from_kind, "Step");
    assert.equal(constrainDiagnostics[0].to_kind, "Goal");
    assert.equal(constrainDiagnostics[1].from_kind, "Invariant");
    assert.equal(constrainDiagnostics[1].to_kind, "Completion");
    assert.deepEqual(constrainDiagnostics[1].supported_roles, [
      { from_kind: "Invariant", to_kind: "Goal" },
    ]);
    assert.equal(guardRoleDiagnostics.length, 3);
    assert.equal(guardRoleDiagnostics[0].from_kind, "Goal");
    assert.equal(guardRoleDiagnostics[0].to_kind, "Completion");
    assert.equal(guardRoleDiagnostics[1].from_kind, "Invariant");
    assert.equal(guardRoleDiagnostics[1].to_kind, "Goal");
    assert.equal(guardRoleDiagnostics[2].from_kind, "Invariant");
    assert.equal(guardRoleDiagnostics[2].to_kind, "Check");
    assert.equal(guardRoleDiagnostics[2].to_scope, "goal");
    assert.deepEqual(guardRoleDiagnostics[2].supported_roles, [
      { from_kind: "Invariant", to_kind: "Completion" },
      { from_kind: "Invariant", to_kind: "Effect" },
      { from_kind: "Invariant", to_kind: "Checkpoint" },
      { from_kind: "Invariant", to_kind: "Policy" },
      { from_kind: "Invariant", to_kind: "Check", to_scope: "step" },
    ]);
  });

  it("validates graph step attachment edge role diagnostics", () => {
    const diagnostics = validateTestGraph({
      source: "synthetic.intent",
      nodes: [
        { id: "goal:demo", kind: "Goal", label: "demo", span: testSpan(1) },
        { id: "goal:demo:step:patch", kind: "Step", label: "patch", span: testSpan(2), data: { effects: ["FileWrite"], requirements: ["synthetic"], checkpoints: ["before patch"], timeouts: ["5m"], retries: ["5m"] } },
        { id: "goal:demo:step:patch:input:0", kind: "Input", label: "input", span: testSpan(3), data: { scope: "step" } },
        { id: "goal:demo:step:patch:requirement:0", kind: "Check", label: "input.ready", span: testSpan(4), data: { scope: "step" } },
        { id: "goal:demo:verify:0", kind: "Check", label: "ok", span: testSpan(5), data: { scope: "goal" } },
        { id: "goal:demo:step:patch:approval:0", kind: "Approval", label: "maintainer", span: testSpan(6) },
        { id: "goal:demo:step:patch:effect:0", kind: "Effect", label: "FileWrite", span: testSpan(7) },
        { id: "goal:demo:step:patch:checkpoint:0", kind: "Checkpoint", label: "before", span: testSpan(8) },
        { id: "goal:demo:step:patch:timeout:0", kind: "Policy", label: "5m", span: testSpan(9), data: { policyKind: "timeout" } },
        { id: "goal:demo:step:patch:retry:0", kind: "Policy", label: "max 2", span: testSpan(10), data: { policyKind: "retry" } },
      ],
      edges: [
        { from: "goal:demo:step:patch:input:0", to: "goal:demo:step:patch", kind: "requires", data: { parameter: "input", type: "Finding", targetSpan: testSpan(2) } },
        { from: "goal:demo:step:patch:requirement:0", to: "goal:demo:step:patch", kind: "requires", data: { requirement: "input.ready" } },
        { from: "goal:demo:step:patch:approval:0", to: "goal:demo:step:patch", kind: "approves", data: { approval: "maintainer" } },
        { from: "goal:demo:step:patch:approval:0", to: "goal:demo:step:patch:effect:0", kind: "approves", data: { approval: "maintainer" } },
        { from: "goal:demo:step:patch", to: "goal:demo:step:patch:checkpoint:0", kind: "checkpoints", data: { checkpoint: "before" } },
        { from: "goal:demo:step:patch:timeout:0", to: "goal:demo:step:patch", kind: "timeouts", data: { policy: "5m" } },
        { from: "goal:demo:step:patch:retry:0", to: "goal:demo:step:patch", kind: "retries", data: { policy: "max 2" } },
        { from: "goal:demo", to: "goal:demo:step:patch", kind: "requires", data: { parameter: "goal", type: "Finding", targetSpan: testSpan(2) } },
        { from: "goal:demo:verify:0", to: "goal:demo:step:patch", kind: "requires", data: { requirement: "ok" } },
        { from: "goal:demo:step:patch", to: "goal:demo:step:patch", kind: "approves", data: { approval: "maintainer" } },
        { from: "goal:demo:step:patch:approval:0", to: "goal:demo:step:patch:checkpoint:0", kind: "approves", data: { approval: "maintainer" } },
        { from: "goal:demo:step:patch:approval:0", to: "goal:demo:step:patch:checkpoint:0", kind: "checkpoints", data: { checkpoint: "before" } },
        { from: "goal:demo:step:patch", to: "goal:demo:step:patch:effect:0", kind: "checkpoints", data: { checkpoint: "before" } },
        { from: "goal:demo:step:patch", to: "goal:demo:step:patch:timeout:0", kind: "timeouts", data: { policy: "5m" } },
        { from: "goal:demo:step:patch:timeout:0", to: "goal:demo:step:patch:effect:0", kind: "timeouts", data: { policy: "5m" } },
        { from: "goal:demo:step:patch:checkpoint:0", to: "goal:demo:step:patch", kind: "retries", data: { policy: "max 2" } },
        { from: "goal:demo:step:patch:retry:0", to: "goal:demo:step:patch:checkpoint:0", kind: "retries", data: { policy: "max 2" } },
      ],
    });
    const requireDiagnostics = diagnostics.filter((diagnostic) => diagnostic.code === "INTENT_GRAPH_REQUIRE_INVALID");
    const approveDiagnostics = diagnostics.filter((diagnostic) => diagnostic.code === "INTENT_GRAPH_APPROVE_INVALID");
    const checkpointDiagnostics = diagnostics.filter((diagnostic) => diagnostic.code === "INTENT_GRAPH_CHECKPOINT_EDGE_INVALID");
    const policyDiagnostics = diagnostics.filter((diagnostic) => diagnostic.code === "INTENT_GRAPH_POLICY_EDGE_INVALID");

    assert.equal(requireDiagnostics.length, 2);
    assert.equal(requireDiagnostics[0].from_kind, "Goal");
    assert.equal(requireDiagnostics[0].to_kind, "Step");
    assert.equal(requireDiagnostics[1].from_kind, "Check");
    assert.equal(requireDiagnostics[1].from_scope, "goal");
    assert.deepEqual(requireDiagnostics[1].supported_roles, [
      { from_kind: "Input", to_kind: "Step" },
      { from_kind: "Check", from_scope: "step", to_kind: "Step" },
    ]);
    assert.equal(approveDiagnostics.length, 2);
    assert.equal(approveDiagnostics[0].from_kind, "Step");
    assert.equal(approveDiagnostics[0].to_kind, "Step");
    assert.equal(approveDiagnostics[1].from_kind, "Approval");
    assert.equal(approveDiagnostics[1].to_kind, "Checkpoint");
    assert.deepEqual(approveDiagnostics[1].supported_roles, [
      { from_kind: "Approval", to_kind: "Step" },
      { from_kind: "Approval", to_kind: "Effect" },
    ]);
    assert.equal(checkpointDiagnostics.length, 2);
    assert.equal(checkpointDiagnostics[0].from_kind, "Approval");
    assert.equal(checkpointDiagnostics[0].to_kind, "Checkpoint");
    assert.equal(checkpointDiagnostics[1].from_kind, "Step");
    assert.equal(checkpointDiagnostics[1].to_kind, "Effect");
    assert.deepEqual(checkpointDiagnostics[1].supported_roles, [
      { from_kind: "Step", to_kind: "Checkpoint" },
    ]);
    assert.equal(policyDiagnostics.length, 4);
    assert.equal(policyDiagnostics[0].edge, "timeouts");
    assert.equal(policyDiagnostics[0].from_kind, "Step");
    assert.equal(policyDiagnostics[0].to_kind, "Policy");
    assert.equal(policyDiagnostics[1].edge, "timeouts");
    assert.equal(policyDiagnostics[1].from_kind, "Policy");
    assert.equal(policyDiagnostics[1].to_kind, "Effect");
    assert.equal(policyDiagnostics[2].edge, "retries");
    assert.equal(policyDiagnostics[2].from_kind, "Checkpoint");
    assert.equal(policyDiagnostics[2].to_kind, "Step");
    assert.equal(policyDiagnostics[3].edge, "retries");
    assert.equal(policyDiagnostics[3].from_kind, "Policy");
    assert.equal(policyDiagnostics[3].to_kind, "Checkpoint");
    assert.deepEqual(policyDiagnostics[3].supported_roles, [
      { from_kind: "Policy", to_kind: "Step" },
    ]);
  });

  it("validates graph data and topology edge role diagnostics", () => {
    const diagnostics = validateTestGraph({
      source: "synthetic.intent",
      nodes: [
        { id: "goal:demo", kind: "Goal", label: "demo", span: testSpan(1) },
        { id: "goal:other", kind: "Goal", label: "other", span: testSpan(2) },
        { id: "goal:demo:input:a", kind: "Input", label: "a", span: testSpan(3), data: { scope: "goal" } },
        { id: "goal:demo:step:patch", kind: "Step", label: "patch", span: testSpan(4) },
        { id: "goal:demo:step:verify", kind: "Step", label: "verify", span: testSpan(5) },
        { id: "goal:demo:step:patch:input:input", kind: "Input", label: "input", span: testSpan(6), data: { scope: "step" } },
        { id: "goal:demo:context:repo", kind: "Context", label: "repo", span: testSpan(7) },
        { id: "goal:demo:completion", kind: "Completion", label: "demo", span: testSpan(8) },
      ],
      edges: [
        { from: "goal:demo:input:a", to: "goal:demo:step:patch:input:input", kind: "data", data: { parameter: "input", type: "Finding", sourceSpan: testSpan(3), targetSpan: testSpan(6) } },
        { from: "goal:demo:step:patch", to: "goal:demo:step:patch:input:input", kind: "data", data: { parameter: "input", type: "Finding", sourceSpan: testSpan(4), targetSpan: testSpan(6) } },
        { from: "goal:demo:input:a", to: "goal:demo", kind: "supplies" },
        { from: "goal:demo:context:repo", to: "goal:demo", kind: "informs" },
        { from: "goal:demo:step:patch", to: "goal:demo:step:verify", kind: "precedes" },
        { from: "goal:demo", to: "goal:demo:step:patch:input:input", kind: "data", data: { parameter: "input", type: "Finding", sourceSpan: testSpan(1), targetSpan: testSpan(6) } },
        { from: "goal:demo:input:a", to: "goal:demo:step:patch", kind: "data", data: { parameter: "input", type: "Finding", sourceSpan: testSpan(3), targetSpan: testSpan(4) } },
        { from: "goal:demo:step:patch:input:input", to: "goal:demo", kind: "supplies" },
        { from: "goal:demo:input:a", to: "goal:demo:completion", kind: "supplies" },
        { from: "goal:demo", to: "goal:demo:context:repo", kind: "informs" },
        { from: "goal:demo:context:repo", to: "goal:demo:completion", kind: "informs" },
        { from: "goal:demo", to: "goal:demo:step:verify", kind: "precedes" },
        { from: "goal:demo:step:patch", to: "goal:demo:completion", kind: "precedes" },
      ],
    });
    const dataDiagnostics = diagnostics.filter((diagnostic) => diagnostic.code === "INTENT_GRAPH_DATA_ROLE_INVALID");
    const supplyDiagnostics = diagnostics.filter((diagnostic) => diagnostic.code === "INTENT_GRAPH_SUPPLY_INVALID");
    const informDiagnostics = diagnostics.filter((diagnostic) => diagnostic.code === "INTENT_GRAPH_INFORM_INVALID");
    const precedeDiagnostics = diagnostics.filter((diagnostic) => diagnostic.code === "INTENT_GRAPH_PRECEDE_INVALID");

    assert.equal(dataDiagnostics.length, 2);
    assert.equal(dataDiagnostics[0].from_kind, "Goal");
    assert.equal(dataDiagnostics[0].to_kind, "Input");
    assert.equal(dataDiagnostics[1].from_kind, "Input");
    assert.equal(dataDiagnostics[1].to_kind, "Step");
    assert.deepEqual(dataDiagnostics[1].supported_roles, [
      { from_kind: "Input", from_scope: "goal", to_kind: "Input", to_scope: "step" },
      { from_kind: "Step", to_kind: "Input", to_scope: "step" },
    ]);
    assert.equal(supplyDiagnostics.length, 2);
    assert.equal(supplyDiagnostics[0].from_kind, "Input");
    assert.equal(supplyDiagnostics[0].from_scope, "step");
    assert.equal(supplyDiagnostics[1].from_kind, "Input");
    assert.equal(supplyDiagnostics[1].to_kind, "Completion");
    assert.deepEqual(supplyDiagnostics[1].supported_roles, [
      { from_kind: "Input", from_scope: "goal", to_kind: "Goal" },
    ]);
    assert.equal(informDiagnostics.length, 2);
    assert.equal(informDiagnostics[0].from_kind, "Goal");
    assert.equal(informDiagnostics[0].to_kind, "Context");
    assert.equal(informDiagnostics[1].from_kind, "Context");
    assert.equal(informDiagnostics[1].to_kind, "Completion");
    assert.deepEqual(informDiagnostics[1].supported_roles, [
      { from_kind: "Context", to_kind: "Goal" },
    ]);
    assert.equal(precedeDiagnostics.length, 2);
    assert.equal(precedeDiagnostics[0].from_kind, "Goal");
    assert.equal(precedeDiagnostics[0].to_kind, "Step");
    assert.equal(precedeDiagnostics[1].from_kind, "Step");
    assert.equal(precedeDiagnostics[1].to_kind, "Completion");
    assert.deepEqual(precedeDiagnostics[1].supported_roles, [
      { from_kind: "Step", to_kind: "Step" },
    ]);
  });

  it("validates graph memory access edge role diagnostics", () => {
    const diagnostics = validateTestGraph({
      source: "synthetic.intent",
      nodes: [
        { id: "goal:demo:memory:0", kind: "Memory", label: "session", span: testSpan(1) },
        { id: "goal:demo:step:patch", kind: "Step", label: "patch", span: testSpan(2) },
        { id: "goal:demo:completion", kind: "Completion", label: "demo", span: testSpan(3) },
      ],
      edges: [
        { from: "goal:demo:memory:0", to: "goal:demo:step:patch", kind: "reads" },
        { from: "goal:demo:step:patch", to: "goal:demo:memory:0", kind: "writes" },
        { from: "goal:demo:memory:0", to: "goal:demo:step:patch", kind: "cites" },
        { from: "goal:demo:step:patch", to: "goal:demo:memory:0", kind: "reads" },
        { from: "goal:demo:memory:0", to: "goal:demo:step:patch", kind: "writes" },
        { from: "goal:demo:completion", to: "goal:demo:step:patch", kind: "cites" },
      ],
    });
    const memoryDiagnostics = diagnostics.filter((diagnostic) => diagnostic.code === "INTENT_GRAPH_MEMORY_ACCESS_INVALID");

    assert.equal(memoryDiagnostics.length, 3);
    assert.equal(memoryDiagnostics[0].edge, "reads");
    assert.equal(memoryDiagnostics[0].from_kind, "Step");
    assert.equal(memoryDiagnostics[0].to_kind, "Memory");
    assert.equal(memoryDiagnostics[1].edge, "writes");
    assert.equal(memoryDiagnostics[1].from_kind, "Memory");
    assert.equal(memoryDiagnostics[1].to_kind, "Step");
    assert.equal(memoryDiagnostics[2].edge, "cites");
    assert.equal(memoryDiagnostics[2].from_kind, "Completion");
    assert.deepEqual(memoryDiagnostics[2].supported_roles, [
      { edge: "reads", from_kind: "Memory", to_kind: "Step" },
      { edge: "cites", from_kind: "Memory", to_kind: "Step" },
      { edge: "writes", from_kind: "Step", to_kind: "Memory" },
    ]);
  });

  it("validates graph memory target diagnostics", () => {
    const diagnostics = validateTestGraph({
      source: "synthetic.intent",
      nodes: [
        { id: "goal:demo:memory:0", kind: "Memory", label: "session", span: testSpan(1), data: { retentionRules: [{ raw: "retain summaries until goal_complete", subject: { raw: "summaries" }, until: { raw: "goal_complete" } }] } },
        { id: "goal:demo:step:patch", kind: "Step", label: "patch", span: testSpan(2) },
      ],
      edges: [
        { from: "goal:demo:memory:0", to: "goal:demo:step:patch", kind: "reads", data: { access: "read", memory: "session", key: "evidence", target: "session.evidence", sourceSpan: testSpan(1), targetSpan: testSpan(2) } },
        { from: "goal:demo:step:patch", to: "goal:demo:memory:0", kind: "writes", data: { access: "write", memory: "session", key: "logs", target: "session.logs", sourceSpan: testSpan(2), targetSpan: testSpan(1) } },
      ],
    }).filter((diagnostic) => diagnostic.code === "INTENT_GRAPH_MEMORY_TARGET_INVALID");

    assert.equal(diagnostics.length, 2);
    assert.equal(diagnostics[0].edge, "reads");
    assert.equal(diagnostics[0].key, "evidence");
    assert.deepEqual(diagnostics[0].declared_keys, ["summaries"]);
    assert.equal(diagnostics[1].edge, "writes");
    assert.equal(diagnostics[1].key, "logs");
  });

  it("validates graph trust metadata diagnostics", () => {
    const diagnostics = validateTestGraph({
      source: "synthetic.intent",
      nodes: [
        { id: "context:missing-trust", kind: "Context", label: "missing trust", span: testSpan(1), data: { trust: null } },
        { id: "context:bad-zone", kind: "Context", label: "bad zone", span: testSpan(2), data: { trust: { zone: "ambient", source: "external" } } },
        { id: "context:blank-source", kind: "Context", label: "blank source", span: testSpan(3), data: { trust: { zone: "trusted", source: "   ", argument: "" } } },
      ],
      edges: [],
    });

    assert.equal(diagnostics.length, 3);
    assert.equal(diagnostics[0].code, "INTENT_GRAPH_TRUST_INVALID");
    assert.equal(diagnostics[0].node_id, "context:missing-trust");
    assert.equal(diagnostics[0].trust_path, "data.trust");
    assert.equal(diagnostics[0].zone_is_supported, false);
    assert.equal(diagnostics[0].source_is_nonempty, false);
    assert.equal(diagnostics[0].argument_is_valid, false);
    assert.equal(diagnostics[1].code, "INTENT_GRAPH_TRUST_INVALID");
    assert.equal(diagnostics[1].trust_zone, "ambient");
    assert.equal(diagnostics[1].zone_is_supported, false);
    assert.equal(diagnostics[1].source_is_nonempty, true);
    assert.equal(diagnostics[1].argument_is_valid, true);
    assert.equal(diagnostics[2].code, "INTENT_GRAPH_TRUST_INVALID");
    assert.equal(diagnostics[2].trust_zone, "trusted");
    assert.equal(diagnostics[2].source_is_nonempty, false);
    assert.equal(diagnostics[2].argument_is_valid, false);
  });

  it("validates graph capability policy diagnostics", () => {
    const diagnostics = validateTestGraph({
      source: "synthetic.intent",
      nodes: [
        { id: "capability:missing-policy", kind: "Capability", label: "missing policy", span: testSpan(1), data: { grants: null } },
        { id: "capability:bad-policy", kind: "Capability", label: "bad policy", span: testSpan(2), data: { family: "file", grants: [], approvalPolicy: "sometimes" } },
        { id: "capability:blank-family", kind: "Capability", label: "blank family", span: testSpan(3), data: { family: "   ", grants: [], approvalPolicy: "required" } },
        { id: "capability:bad-grants", kind: "Capability", label: "bad grants", span: testSpan(4), data: { grants: [{ action: "", key: "path", value: "./src/**", raw: "read path: \"./src/**\"", span: testSpan(4) }, { action: "read", key: "path", value: "./src/**", raw: "" }] } },
        {
          id: "capability:stale-contract",
          kind: "Capability",
          label: "stale contract",
          span: testSpan(5),
          data: {
            family: "shell",
            grants: [{
              ...testGrant("run", "command", "npm test", 5),
              contractId: "intent.effect.file.write.v0",
              contractArgument: "command",
            }],
          },
        },
      ],
      edges: [],
    });

    assert.equal(diagnostics.length, 5);
    assert.equal(diagnostics[0].code, "INTENT_GRAPH_CAPABILITY_INVALID");
    assert.equal(diagnostics[0].capability_id, "capability:missing-policy");
    assert.equal(diagnostics[0].family_is_nonempty, true);
    assert.equal(diagnostics[0].grants_is_array, false);
    assert.equal(diagnostics[0].approval_policy_is_valid, true);
    assert.equal(diagnostics[1].code, "INTENT_GRAPH_CAPABILITY_INVALID");
    assert.equal(diagnostics[1].approval_policy, "sometimes");
    assert.equal(diagnostics[1].family_is_nonempty, true);
    assert.equal(diagnostics[1].grants_is_array, true);
    assert.equal(diagnostics[1].approval_policy_is_valid, false);
    assert.equal(diagnostics[2].code, "INTENT_GRAPH_CAPABILITY_INVALID");
    assert.equal(diagnostics[2].family, "   ");
    assert.equal(diagnostics[2].family_is_nonempty, false);
    assert.equal(diagnostics[3].code, "INTENT_GRAPH_CAPABILITY_INVALID");
    assert.equal(diagnostics[3].capability_id, "capability:bad-grants");
    assert.deepEqual(diagnostics[3].invalid_grant_indexes, [0, 1]);
    assert.equal(diagnostics[4].capability_id, "capability:stale-contract");
    assert.deepEqual(diagnostics[4].invalid_grant_indexes, [0]);
  });

  it("validates graph memory retention diagnostics", () => {
    const diagnostics = validateTestGraph({
      source: "synthetic.intent",
      nodes: [
        { id: "memory:missing-retention", kind: "Memory", label: "missing retention", span: testSpan(1), data: { retention: null } },
        { id: "memory:empty-rules", kind: "Memory", label: "empty rules", span: testSpan(2), data: { retentionRules: [] } },
        {
          id: "memory:bad-rule",
          kind: "Memory",
          label: "bad rule",
          span: testSpan(3),
          data: { retentionRules: [{ raw: "retain evidence until forever", subject: { raw: "evidence" }, until: { raw: "forever" } }] },
        },
      ],
      edges: [],
    });

    assert.equal(diagnostics.length, 3);
    assert.equal(diagnostics[0].code, "INTENT_GRAPH_MEMORY_INVALID");
    assert.equal(diagnostics[0].memory_id, "memory:missing-retention");
    assert.equal(diagnostics[0].retention_is_array, false);
    assert.equal(diagnostics[0].retention_rules_is_array, true);
    assert.equal(diagnostics[0].retention_rules_nonempty, true);
    assert.deepEqual(diagnostics[0].invalid_retention_indexes, []);
    assert.equal(diagnostics[1].code, "INTENT_GRAPH_MEMORY_INVALID");
    assert.equal(diagnostics[1].retention_is_array, true);
    assert.equal(diagnostics[1].retention_rules_nonempty, false);
    assert.equal(diagnostics[2].code, "INTENT_GRAPH_MEMORY_INVALID");
    assert.deepEqual(diagnostics[2].invalid_retention_indexes, [0]);
  });

  it("validates graph memory declaration diagnostics", () => {
    const diagnostics = validateTestGraph({
      source: "synthetic.intent",
      nodes: [
        { id: "goal:demo", kind: "Goal", label: "demo", span: testSpan(1) },
        { id: "goal:other", kind: "Goal", label: "other", span: testSpan(2) },
        { id: "goal:demo:memory:missing", kind: "Memory", label: "missing", span: testSpan(3) },
        { id: "goal:demo:memory:wrong", kind: "Memory", label: "wrong", span: testSpan(4) },
        { id: "goal:demo:memory:duplicate", kind: "Memory", label: "duplicate", span: testSpan(5) },
        { id: "goal:demo:memory:valid", kind: "Memory", label: "valid", span: testSpan(6) },
      ],
      edges: [
        { from: "goal:other", to: "goal:demo:memory:wrong", kind: "declares" },
        { from: "goal:demo", to: "goal:demo:memory:duplicate", kind: "declares" },
        { from: "goal:demo", to: "goal:demo:memory:duplicate", kind: "declares" },
        { from: "goal:demo", to: "goal:demo:memory:valid", kind: "declares" },
      ],
    }).filter((diagnostic) => diagnostic.code === "INTENT_GRAPH_MEMORY_DECLARE_INVALID");

    assert.equal(diagnostics.length, 3);
    assert.equal(diagnostics[0].memory_id, "goal:demo:memory:missing");
    assert.equal(diagnostics[0].declares_edges, 0);
    assert.equal(diagnostics[0].owner_goal_declares_edges, 0);
    assert.equal(diagnostics[1].memory_id, "goal:demo:memory:wrong");
    assert.equal(diagnostics[1].declares_edges, 1);
    assert.equal(diagnostics[1].owner_goal_declares_edges, 0);
    assert.equal(diagnostics[1].wrong_goal_declares_edges, 1);
    assert.equal(diagnostics[2].memory_id, "goal:demo:memory:duplicate");
    assert.equal(diagnostics[2].declares_edges, 2);
    assert.equal(diagnostics[2].owner_goal_declares_edges, 2);
  });

  it("validates graph memory declaration metadata diagnostics", () => {
    const goalSpan = testSpan(1);
    const memorySpan = testSpan(2);
    const diagnostics = validateTestGraph({
      source: "synthetic.intent",
      nodes: [
        { id: "goal:demo", kind: "Goal", label: "demo", span: goalSpan },
        { id: "goal:demo:memory:0", kind: "Memory", label: "session", span: memorySpan, data: { scope: "session" } },
      ],
      edges: [
        {
          from: "goal:demo",
          to: "goal:demo:memory:0",
          kind: "declares",
          data: {
            goal: "demo",
            memory: "wrong",
            memoryScope: "session",
            sourceSpan: goalSpan,
            targetSpan: memorySpan,
          },
        },
      ],
    }).filter((diagnostic) => diagnostic.code === "INTENT_GRAPH_MEMORY_DECLARE_INVALID");

    assert.equal(diagnostics.length, 1);
    assert.equal(diagnostics[0].data_is_object, true);
    assert.equal(diagnostics[0].goal_matches_source, true);
    assert.equal(diagnostics[0].memory_matches_target, false);
    assert.equal(diagnostics[0].memory_scope_matches_target, true);
    assert.equal(diagnostics[0].source_span_matches_goal, true);
    assert.equal(diagnostics[0].target_span_matches_memory, true);
  });

  it("validates graph type declaration diagnostics", () => {
    const diagnostics = validateTestGraph({
      source: "synthetic.intent",
      nodes: [
        { id: "type:blank-definition", kind: "Type", label: "BlankDefinition", span: testSpan(1), data: { definition: "" } },
        { id: "type:bad-definition", kind: "Type", label: "BadDefinition", span: testSpan(2), data: { definition: { field: "String" } } },
      ],
      edges: [],
    }).filter((diagnostic) => diagnostic.code === "INTENT_GRAPH_TYPE_INVALID");

    assert.equal(diagnostics.length, 2);
    assert.equal(diagnostics[0].code, "INTENT_GRAPH_TYPE_INVALID");
    assert.equal(diagnostics[0].type_id, "type:blank-definition");
    assert.equal(diagnostics[0].definition_is_valid, false);
    assert.equal(diagnostics[1].code, "INTENT_GRAPH_TYPE_INVALID");
    assert.equal(diagnostics[1].type_id, "type:bad-definition");
    assert.equal(diagnostics[1].definition_is_valid, false);
  });

  it("validates graph type availability declaration diagnostics", () => {
    const diagnostics = validateTestGraph({
      source: "synthetic.intent",
      nodes: [
        { id: "goal:demo", kind: "Goal", label: "demo", span: testSpan(1) },
        { id: "goal:other", kind: "Goal", label: "other", span: testSpan(2) },
        { id: "type:missing", kind: "Type", label: "Missing", span: testSpan(3) },
        { id: "type:partial", kind: "Type", label: "Partial", span: testSpan(4) },
        { id: "type:duplicate", kind: "Type", label: "Duplicate", span: testSpan(5) },
        { id: "type:wrong", kind: "Type", label: "Wrong", span: testSpan(6) },
        { id: "type:valid", kind: "Type", label: "Valid", span: testSpan(7) },
        { id: "goal:demo:memory:0", kind: "Memory", label: "memory", span: testSpan(8) },
      ],
      edges: [
        { from: "type:partial", to: "goal:demo", kind: "declares" },
        { from: "type:duplicate", to: "goal:demo", kind: "declares" },
        { from: "type:duplicate", to: "goal:demo", kind: "declares" },
        { from: "type:duplicate", to: "goal:other", kind: "declares" },
        { from: "type:wrong", to: "goal:demo", kind: "declares" },
        { from: "type:wrong", to: "goal:other", kind: "declares" },
        { from: "type:wrong", to: "goal:demo:memory:0", kind: "declares" },
        { from: "type:valid", to: "goal:demo", kind: "declares" },
        { from: "type:valid", to: "goal:other", kind: "declares" },
        { from: "goal:demo", to: "goal:demo:memory:0", kind: "declares" },
      ],
    }).filter((diagnostic) => diagnostic.code === "INTENT_GRAPH_TYPE_DECLARE_INVALID");

    assert.equal(diagnostics.length, 3);
    assert.equal(diagnostics[0].type_id, "type:missing");
    assert.deepEqual(diagnostics[0].missing_goal_ids, ["goal:demo", "goal:other"]);
    assert.equal(diagnostics[0].declares_edges, 0);
    assert.equal(diagnostics[1].type_id, "type:partial");
    assert.deepEqual(diagnostics[1].missing_goal_ids, ["goal:other"]);
    assert.equal(diagnostics[2].type_id, "type:duplicate");
    assert.deepEqual(diagnostics[2].duplicate_goal_ids, ["goal:demo"]);
    assert.equal(diagnostics[2].declares_edges, 3);
  });

  it("validates graph type availability declaration metadata diagnostics", () => {
    const typeSpan = testSpan(1);
    const goalSpan = testSpan(2);
    const diagnostics = validateTestGraph({
      source: "synthetic.intent",
      nodes: [
        { id: "type:ticket", kind: "Type", label: "Ticket", span: typeSpan, data: { definition: "{ id: String }" } },
        { id: "goal:demo", kind: "Goal", label: "demo", span: goalSpan },
      ],
      edges: [
        {
          from: "type:ticket",
          to: "goal:demo",
          kind: "declares",
          data: {
            type: "Ticket",
            definition: "{ id: String }",
            goal: "wrong",
            sourceSpan: typeSpan,
            targetSpan: goalSpan,
          },
        },
      ],
    }).filter((diagnostic) => diagnostic.code === "INTENT_GRAPH_TYPE_DECLARE_INVALID");

    assert.equal(diagnostics.length, 1);
    assert.equal(diagnostics[0].invalid_declare_metadata.length, 1);
    assert.equal(diagnostics[0].invalid_declare_metadata[0].data_is_object, true);
    assert.equal(diagnostics[0].invalid_declare_metadata[0].type_matches_source, true);
    assert.equal(diagnostics[0].invalid_declare_metadata[0].goal_matches_target, false);
    assert.equal(diagnostics[0].invalid_declare_metadata[0].source_span_matches_type, true);
    assert.equal(diagnostics[0].invalid_declare_metadata[0].target_span_matches_goal, true);
  });

  it("validates graph goal typed contract diagnostics", () => {
    const diagnostics = validateTestGraph({
      source: "synthetic.intent",
      nodes: [
        { id: "goal:bad-title", kind: "Goal", label: "bad title", span: testSpan(1), data: { title: "" } },
        { id: "goal:bad-parameters", kind: "Goal", label: "bad parameters", span: testSpan(2), data: { parameters: [{ name: "", type: "Finding", span: testSpan(2) }] } },
        { id: "goal:bad-output", kind: "Goal", label: "bad output", span: testSpan(3), data: { outputType: "", outputTypeSpan: { file: "synthetic.intent", start: { line: 0, column: 1 }, end: { line: 1, column: 1 } } } },
        { id: "goal:missing-output-span", kind: "Goal", label: "missing output span", span: testSpan(4), data: { outputType: "Report", outputTypeSpan: null } },
        { id: "goal:unexpected-output-span", kind: "Goal", label: "unexpected output span", span: testSpan(5), data: { outputType: null, outputTypeSpan: testSpan(5) } },
      ],
      edges: [],
    }).filter((diagnostic) => diagnostic.code === "INTENT_GRAPH_GOAL_INVALID");

    assert.equal(diagnostics.length, 5);
    assert.equal(diagnostics[0].code, "INTENT_GRAPH_GOAL_INVALID");
    assert.equal(diagnostics[0].goal_id, "goal:bad-title");
    assert.equal(diagnostics[0].title_is_valid, false);
    assert.equal(diagnostics[1].code, "INTENT_GRAPH_GOAL_INVALID");
    assert.deepEqual(diagnostics[1].invalid_parameter_indexes, [0]);
    assert.equal(diagnostics[2].code, "INTENT_GRAPH_GOAL_INVALID");
    assert.equal(diagnostics[2].output_type_is_valid, false);
    assert.equal(diagnostics[2].output_type_span_is_valid, false);
    assert.equal(diagnostics[3].goal_id, "goal:missing-output-span");
    assert.equal(diagnostics[3].output_type_is_valid, true);
    assert.equal(diagnostics[3].output_type_span_is_valid, false);
    assert.equal(diagnostics[4].goal_id, "goal:unexpected-output-span");
    assert.equal(diagnostics[4].output_type_is_valid, true);
    assert.equal(diagnostics[4].output_type_span_is_valid, false);
  });

  it("validates graph goal metadata diagnostics", () => {
    const diagnostics = validateTestGraph({
      source: "synthetic.intent",
      nodes: [
        { id: "goal:demo", kind: "Goal", label: "demo", span: testSpan(1), data: {
          parameters: [{ name: "ticket", type: "Ticket", span: testSpan(2) }],
          outputType: "Report",
          outputTypeSpan: testSpan(3),
        } },
        { id: "goal:demo:input:ticket", kind: "Input", label: "ticket", span: testSpan(2), data: { scope: "goal", type: "Finding" } },
        { id: "goal:demo:completion", kind: "Completion", label: "demo", span: testSpan(4), data: { outputType: "Patch", outputTypeSpan: testSpan(4) } },
      ],
      edges: [
        { from: "goal:demo:input:ticket", to: "goal:demo", kind: "supplies", data: { parameter: "ticket", type: "Finding", sourceSpan: testSpan(2), targetSpan: testSpan(2) } },
        { from: "goal:demo", to: "goal:demo:completion", kind: "completes" },
      ],
    }).filter((diagnostic) => diagnostic.code === "INTENT_GRAPH_GOAL_METADATA_INVALID");

    assert.deepEqual(diagnostics.map((diagnostic) => diagnostic.field), ["parameters", "outputType"]);
    assert.deepEqual(diagnostics[0].declared_values.map((parameter) => parameter.type), ["Ticket"]);
    assert.deepEqual(diagnostics[0].owned_values.map((parameter) => parameter.type), ["Finding"]);
    assert.deepEqual(diagnostics[0].owned_node_ids, ["goal:demo:input:ticket"]);
    assert.equal(diagnostics[0].declared_count, 1);
    assert.equal(diagnostics[0].owned_count, 1);
    assert.deepEqual(diagnostics[0].mismatched_indexes, [0]);
    assert.equal(diagnostics[1].declared_value.outputType, "Report");
    assert.equal(diagnostics[1].owned_value.outputType, "Patch");
    assert.deepEqual(diagnostics[1].owned_node_ids, ["goal:demo:completion"]);
  });

  it("validates graph step policy diagnostics", () => {
    const diagnostics = validateTestGraph({
      source: "synthetic.intent",
      nodes: [
        { id: "policy:missing", kind: "Policy", label: "missing policy", span: testSpan(1), data: { policy: null } },
        { id: "policy:bad-kind", kind: "Policy", label: "bad kind", span: testSpan(2), data: { policyKind: "budget", policy: "5m", ownerStep: "patch" } },
        { id: "policy:blank-owner", kind: "Policy", label: "blank owner", span: testSpan(3), data: { policyKind: "retry", policy: "   ", ownerStep: "" } },
      ],
      edges: [],
    }).filter((diagnostic) => diagnostic.code === "INTENT_GRAPH_POLICY_INVALID");

    assert.equal(diagnostics.length, 3);
    assert.equal(diagnostics[0].code, "INTENT_GRAPH_POLICY_INVALID");
    assert.equal(diagnostics[0].policy_id, "policy:missing");
    assert.equal(diagnostics[0].policy_kind_is_valid, true);
    assert.equal(diagnostics[0].policy_is_nonempty, false);
    assert.equal(diagnostics[0].owner_step_is_nonempty, true);
    assert.equal(diagnostics[1].code, "INTENT_GRAPH_POLICY_INVALID");
    assert.equal(diagnostics[1].policy_kind, "budget");
    assert.equal(diagnostics[1].policy_kind_is_valid, false);
    assert.equal(diagnostics[1].policy_is_nonempty, true);
    assert.equal(diagnostics[2].code, "INTENT_GRAPH_POLICY_INVALID");
    assert.equal(diagnostics[2].policy_kind_is_valid, true);
    assert.equal(diagnostics[2].policy_is_nonempty, false);
    assert.equal(diagnostics[2].owner_step_is_nonempty, false);
  });

  it("validates graph step approval diagnostics", () => {
    const diagnostics = validateTestGraph({
      source: "synthetic.intent",
      nodes: [
        { id: "approval:missing", kind: "Approval", label: "missing approval", span: testSpan(1), data: { approval: null } },
        { id: "approval:blank-owner", kind: "Approval", label: "blank owner", span: testSpan(2), data: { approval: "maintainer", ownerStep: "" } },
        { id: "approval:blank-gate", kind: "Approval", label: "blank gate", span: testSpan(3), data: { approval: "   ", ownerStep: "patch" } },
      ],
      edges: [],
    }).filter((diagnostic) => diagnostic.code === "INTENT_GRAPH_APPROVAL_INVALID");

    assert.equal(diagnostics.length, 3);
    assert.equal(diagnostics[0].code, "INTENT_GRAPH_APPROVAL_INVALID");
    assert.equal(diagnostics[0].approval_id, "approval:missing");
    assert.equal(diagnostics[0].approval_is_nonempty, false);
    assert.equal(diagnostics[0].owner_step_is_nonempty, true);
    assert.equal(diagnostics[1].code, "INTENT_GRAPH_APPROVAL_INVALID");
    assert.equal(diagnostics[1].approval_gate, "maintainer");
    assert.equal(diagnostics[1].approval_is_nonempty, true);
    assert.equal(diagnostics[1].owner_step_is_nonempty, false);
    assert.equal(diagnostics[2].code, "INTENT_GRAPH_APPROVAL_INVALID");
    assert.equal(diagnostics[2].approval_gate, "   ");
    assert.equal(diagnostics[2].approval_is_nonempty, false);
    assert.equal(diagnostics[2].owner_step_is_nonempty, true);
  });

  it("validates graph step checkpoint diagnostics", () => {
    const diagnostics = validateTestGraph({
      source: "synthetic.intent",
      nodes: [
        { id: "checkpoint:missing", kind: "Checkpoint", label: "missing checkpoint", span: testSpan(1), data: { checkpoint: null } },
        { id: "checkpoint:blank-owner", kind: "Checkpoint", label: "blank owner", span: testSpan(2), data: { checkpoint: "before patch", ownerStep: "" } },
        { id: "checkpoint:blank-value", kind: "Checkpoint", label: "blank value", span: testSpan(3), data: { checkpoint: "   ", ownerStep: "patch" } },
      ],
      edges: [],
    }).filter((diagnostic) => diagnostic.code === "INTENT_GRAPH_CHECKPOINT_INVALID");

    assert.equal(diagnostics.length, 3);
    assert.equal(diagnostics[0].code, "INTENT_GRAPH_CHECKPOINT_INVALID");
    assert.equal(diagnostics[0].checkpoint_id, "checkpoint:missing");
    assert.equal(diagnostics[0].checkpoint_is_nonempty, false);
    assert.equal(diagnostics[0].owner_step_is_nonempty, true);
    assert.equal(diagnostics[1].code, "INTENT_GRAPH_CHECKPOINT_INVALID");
    assert.equal(diagnostics[1].checkpoint_value, "before patch");
    assert.equal(diagnostics[1].checkpoint_is_nonempty, true);
    assert.equal(diagnostics[1].owner_step_is_nonempty, false);
    assert.equal(diagnostics[2].code, "INTENT_GRAPH_CHECKPOINT_INVALID");
    assert.equal(diagnostics[2].checkpoint_value, "   ");
    assert.equal(diagnostics[2].checkpoint_is_nonempty, false);
    assert.equal(diagnostics[2].owner_step_is_nonempty, true);
  });

  it("validates graph effect adapter diagnostics", () => {
    const diagnostics = validateTestGraph({
      source: "synthetic.intent",
      nodes: [
        { id: "effect:missing", kind: "Effect", label: "missing effect", span: testSpan(1), data: { family: null } },
        { id: "effect:bad-spans", kind: "Effect", label: "bad spans", span: testSpan(2), data: { argSpans: { path: "line 1" } } },
        { id: "effect:bad-policy", kind: "Effect", label: "bad policy", span: testSpan(3), data: { family: "   ", action: "", args: null, argKinds: null, approvalRequired: "yes" } },
        {
          id: "effect:stale-contract",
          kind: "Effect",
          label: "stale contract",
          span: testSpan(4),
          data: {
            family: "shell",
            action: "run",
            contractId: "intent.effect.file.write.v0",
            contractArguments: { command: "command" },
            args: { command: "npm test" },
            argKinds: { command: "string" },
            argSpans: { command: testSpan(4) },
            trust: { zone: "trusted", source: "literal", argument: "command" },
            expression: "Command(\"npm test\")",
            approvalRequired: false,
          },
        },
      ],
      edges: [],
    }).filter((diagnostic) => diagnostic.code === "INTENT_GRAPH_EFFECT_INVALID");

    assert.equal(diagnostics.length, 4);
    assert.equal(diagnostics[0].code, "INTENT_GRAPH_EFFECT_INVALID");
    assert.equal(diagnostics[0].effect_id, "effect:missing");
    assert.equal(diagnostics[0].family_is_nonempty, false);
    assert.equal(diagnostics[0].action_is_nonempty, true);
    assert.equal(diagnostics[0].arg_spans_are_valid, true);
    assert.equal(diagnostics[1].code, "INTENT_GRAPH_EFFECT_INVALID");
    assert.equal(diagnostics[1].arg_spans_is_object, true);
    assert.equal(diagnostics[1].arg_spans_are_valid, false);
    assert.equal(diagnostics[2].code, "INTENT_GRAPH_EFFECT_INVALID");
    assert.equal(diagnostics[2].family_is_nonempty, false);
    assert.equal(diagnostics[2].action_is_nonempty, false);
    assert.equal(diagnostics[2].args_is_object, false);
    assert.equal(diagnostics[2].arg_kinds_is_object, false);
    assert.equal(diagnostics[2].approval_required_is_boolean, false);
    assert.equal(diagnostics[3].contract_id, "intent.effect.file.write.v0");
    assert.equal(diagnostics[3].contract_is_known, true);
    assert.equal(diagnostics[3].contract_family_matches, false);
    assert.equal(diagnostics[3].contract_action_matches, false);
    assert.equal(diagnostics[3].contract_arguments_are_valid, false);
  });

  it("validates graph context source diagnostics", () => {
    const diagnostics = validateTestGraph({
      source: "synthetic.intent",
      nodes: [
        { id: "context:missing", kind: "Context", label: "missing context", span: testSpan(1), data: { source: null } },
        { id: "context:bad-spans", kind: "Context", label: "bad spans", span: testSpan(2), data: { argSpans: { path: "line 1" } } },
        { id: "context:bad-shape", kind: "Context", label: "bad shape", span: testSpan(3), data: { source: "   ", expression: "", args: null, argKinds: null } },
        {
          id: "context:bad-contract",
          kind: "Context",
          label: "bad contract",
          span: testSpan(4),
          data: {
            source: "web",
            expression: "web(url: \"https://example.com\")",
            contractId: "intent.effect.file.read.v0",
            contractArguments: { domain: "url" },
            args: { url: "https://example.com" },
            argKinds: { url: "string" },
            argSpans: { url: testSpan(4) },
          },
        },
      ],
      edges: [],
    }).filter((diagnostic) => diagnostic.code === "INTENT_GRAPH_CONTEXT_INVALID");

    assert.equal(diagnostics.length, 4);
    assert.equal(diagnostics[0].code, "INTENT_GRAPH_CONTEXT_INVALID");
    assert.equal(diagnostics[0].context_id, "context:missing");
    assert.equal(diagnostics[0].source_is_nonempty, false);
    assert.equal(diagnostics[0].expression_is_nonempty, true);
    assert.equal(diagnostics[0].arg_spans_are_valid, true);
    assert.equal(diagnostics[1].code, "INTENT_GRAPH_CONTEXT_INVALID");
    assert.equal(diagnostics[1].arg_spans_is_object, true);
    assert.equal(diagnostics[1].arg_spans_are_valid, false);
    assert.equal(diagnostics[2].code, "INTENT_GRAPH_CONTEXT_INVALID");
    assert.equal(diagnostics[2].source_is_nonempty, false);
    assert.equal(diagnostics[2].expression_is_nonempty, false);
    assert.equal(diagnostics[2].args_is_object, false);
    assert.equal(diagnostics[2].arg_kinds_is_object, false);
    assert.equal(diagnostics[3].contract_id, "intent.effect.file.read.v0");
    assert.equal(diagnostics[3].contract_is_known, true);
    assert.equal(diagnostics[3].contract_family_matches, false);
    assert.equal(diagnostics[3].contract_action_matches, true);
    assert.equal(diagnostics[3].contract_arguments_are_valid, false);
  });

  it("validates graph check payload diagnostics", () => {
    const diagnostics = validateTestGraph({
      source: "synthetic.intent",
      nodes: [
        { id: "check:missing", kind: "Check", label: "missing check", span: testSpan(1), data: { requirement: null } },
        { id: "check:bad-step", kind: "Check", label: "bad step", span: testSpan(2), data: { scope: "step", ownerStep: "", assertion: "" } },
        { id: "check:bad-effect", kind: "Check", label: "bad effect", span: testSpan(3), data: { effect: { family: "", action: null, args: null, argKinds: null, argSpans: { command: "line 1" } } } },
      ],
      edges: [],
    }).filter((diagnostic) => diagnostic.code === "INTENT_GRAPH_CHECK_INVALID");

    assert.equal(diagnostics.length, 3);
    assert.equal(diagnostics[0].code, "INTENT_GRAPH_CHECK_INVALID");
    assert.equal(diagnostics[0].check_id, "check:missing");
    assert.equal(diagnostics[0].requirement_is_nonempty, false);
    assert.equal(diagnostics[0].scope_is_valid, true);
    assert.equal(diagnostics[1].code, "INTENT_GRAPH_CHECK_INVALID");
    assert.equal(diagnostics[1].scope, "step");
    assert.equal(diagnostics[1].owner_step_is_valid, false);
    assert.equal(diagnostics[1].assertion_is_valid, false);
    assert.equal(diagnostics[2].code, "INTENT_GRAPH_CHECK_INVALID");
    assert.equal(diagnostics[2].effect_family_is_nonempty, false);
    assert.equal(diagnostics[2].effect_action_is_nonempty, false);
    assert.equal(diagnostics[2].effect_args_is_object, false);
    assert.equal(diagnostics[2].effect_arg_kinds_is_object, false);
    assert.equal(diagnostics[2].effect_arg_spans_is_object, true);
    assert.equal(diagnostics[2].effect_arg_spans_are_valid, false);
  });

  it("validates graph input binding payload diagnostics", () => {
    const diagnostics = validateTestGraph({
      source: "synthetic.intent",
      nodes: [
        { id: "input:missing", kind: "Input", label: "missing input", span: testSpan(1), data: { scope: null, type: null } },
        { id: "input:bad-scope", kind: "Input", label: "bad scope", span: testSpan(2), data: { scope: "job" } },
        { id: "input:bad-type", kind: "Input", label: "bad type", span: testSpan(3), data: { type: "" } },
      ],
      edges: [],
    }).filter((diagnostic) => diagnostic.code === "INTENT_GRAPH_INPUT_INVALID");

    assert.equal(diagnostics.length, 3);
    assert.equal(diagnostics[0].code, "INTENT_GRAPH_INPUT_INVALID");
    assert.equal(diagnostics[0].input_id, "input:missing");
    assert.equal(diagnostics[0].scope_is_valid, false);
    assert.equal(diagnostics[0].type_is_nonempty, false);
    assert.equal(diagnostics[1].code, "INTENT_GRAPH_INPUT_INVALID");
    assert.equal(diagnostics[1].scope, "job");
    assert.equal(diagnostics[1].scope_is_valid, false);
    assert.equal(diagnostics[1].type_is_nonempty, true);
    assert.equal(diagnostics[2].code, "INTENT_GRAPH_INPUT_INVALID");
    assert.equal(diagnostics[2].scope_is_valid, true);
    assert.equal(diagnostics[2].type_is_nonempty, false);
  });

  it("validates graph step plan payload diagnostics", () => {
    const diagnostics = validateTestGraph({
      source: "synthetic.intent",
      nodes: [
        { id: "step:bad-inputs", kind: "Step", label: "bad inputs", span: testSpan(1), data: { inputs: [{ name: "", type: "Finding", span: testSpan(1) }] } },
        { id: "step:bad-output", kind: "Step", label: "bad output", span: testSpan(2), data: { outputType: "", outputTypeSpan: { file: "synthetic.intent", start: { line: 0, column: 1 }, end: { line: 1, column: 1 } } } },
        { id: "step:missing-output-span", kind: "Step", label: "missing output span", span: testSpan(3), data: { outputType: "Report", outputTypeSpan: null } },
        { id: "step:unexpected-output-span", kind: "Step", label: "unexpected output span", span: testSpan(4), data: { outputType: null, outputTypeSpan: testSpan(4) } },
        { id: "step:bad-lists", kind: "Step", label: "bad lists", span: testSpan(5), data: { effects: ["write", ""], requirements: null, checkpoints: ["before"], approvals: [" "], timeouts: ["5m"], retries: ["max 2"] } },
        { id: "step:bad-memory", kind: "Step", label: "bad memory", span: testSpan(6), data: { memoryAccesses: ["session.evidence", ""] } },
      ],
      edges: [],
    }).filter((diagnostic) => diagnostic.code === "INTENT_GRAPH_STEP_INVALID");

    assert.equal(diagnostics.length, 6);
    assert.equal(diagnostics[0].code, "INTENT_GRAPH_STEP_INVALID");
    assert.equal(diagnostics[0].step_id, "step:bad-inputs");
    assert.deepEqual(diagnostics[0].invalid_input_indexes, [0]);
    assert.equal(diagnostics[1].code, "INTENT_GRAPH_STEP_INVALID");
    assert.equal(diagnostics[1].output_type_is_valid, false);
    assert.equal(diagnostics[1].output_type_span_is_valid, false);
    assert.equal(diagnostics[2].step_id, "step:missing-output-span");
    assert.equal(diagnostics[2].output_type_is_valid, true);
    assert.equal(diagnostics[2].output_type_span_is_valid, false);
    assert.equal(diagnostics[3].step_id, "step:unexpected-output-span");
    assert.equal(diagnostics[3].output_type_is_valid, true);
    assert.equal(diagnostics[3].output_type_span_is_valid, false);
    assert.equal(diagnostics[4].code, "INTENT_GRAPH_STEP_INVALID");
    assert.equal(diagnostics[4].effects_are_valid, false);
    assert.equal(diagnostics[4].requirements_are_valid, false);
    assert.equal(diagnostics[4].approvals_are_valid, false);
    assert.equal(diagnostics[4].checkpoints_are_valid, true);
    assert.equal(diagnostics[5].code, "INTENT_GRAPH_STEP_INVALID");
    assert.equal(diagnostics[5].step_id, "step:bad-memory");
    assert.equal(diagnostics[5].memory_accesses_are_valid, false);
  });

  it("validates graph step metadata diagnostics", () => {
    const diagnostics = validateTestGraph({
      source: "synthetic.intent",
      nodes: [
        { id: "goal:demo:step:patch", kind: "Step", label: "patch", span: testSpan(1), data: {
          inputs: [{ name: "ticket", type: "Ticket", span: testSpan(10) }],
          effects: ["ShellRun"],
          requirements: ["ticket.reviewed"],
          checkpoints: ["after patch"],
          approvals: ["lead approves"],
          timeouts: ["10m"],
          retries: ["max 1"],
          memoryAccesses: ["session.summary"],
        } },
        { id: "goal:demo:memory:0", kind: "Memory", label: "session", span: testSpan(2) },
        { id: "goal:demo:step:patch:input:ticket", kind: "Input", label: "ticket", span: testSpan(10), data: { scope: "step", type: "Finding" } },
        { id: "goal:demo:step:patch:effect:0", kind: "Effect", label: "FileWrite", span: testSpan(3) },
        { id: "goal:demo:step:patch:requirement:0", kind: "Check", label: "ready", span: testSpan(4), data: { scope: "step", ownerStep: "patch", requirement: "ticket.ready" } },
        { id: "goal:demo:step:patch:checkpoint:0", kind: "Checkpoint", label: "before", span: testSpan(5), data: { checkpoint: "before patch" } },
        { id: "goal:demo:step:patch:approval:0", kind: "Approval", label: "maintainer", span: testSpan(6), data: { approval: "maintainer approves" } },
        { id: "goal:demo:step:patch:timeout:0", kind: "Policy", label: "5m", span: testSpan(7), data: { policyKind: "timeout", policy: "5m" } },
        { id: "goal:demo:step:patch:retry:0", kind: "Policy", label: "max 2", span: testSpan(8), data: { policyKind: "retry", policy: "max 2" } },
      ],
      edges: [
        { from: "goal:demo:step:patch:input:ticket", to: "goal:demo:step:patch", kind: "requires", data: { parameter: "ticket", type: "Finding", targetSpan: testSpan(10) } },
        { from: "goal:demo:step:patch", to: "goal:demo:step:patch:effect:0", kind: "requests" },
        { from: "goal:demo:step:patch:requirement:0", to: "goal:demo:step:patch", kind: "requires", data: { requirement: "ticket.ready" } },
        { from: "goal:demo:step:patch", to: "goal:demo:step:patch:checkpoint:0", kind: "checkpoints", data: { checkpoint: "before patch" } },
        { from: "goal:demo:step:patch:approval:0", to: "goal:demo:step:patch", kind: "approves", data: { approval: "maintainer approves" } },
        { from: "goal:demo:step:patch:timeout:0", to: "goal:demo:step:patch", kind: "timeouts", data: { policy: "5m" } },
        { from: "goal:demo:step:patch:retry:0", to: "goal:demo:step:patch", kind: "retries", data: { policy: "max 2" } },
        { from: "goal:demo:memory:0", to: "goal:demo:step:patch", kind: "reads", data: { access: "read", memory: "session", key: "evidence", target: "session.evidence", sourceSpan: testSpan(2), targetSpan: testSpan(9) } },
      ],
    }).filter((diagnostic) => diagnostic.code === "INTENT_GRAPH_STEP_METADATA_INVALID");

    assert.deepEqual(diagnostics.map((diagnostic) => diagnostic.field), ["inputs", "effects", "requirements", "checkpoints", "approvals", "timeouts", "retries", "memoryAccesses"]);
    assert.deepEqual(diagnostics[0].declared_values.map((input) => input.type), ["Ticket"]);
    assert.deepEqual(diagnostics[0].owned_values.map((input) => input.type), ["Finding"]);
    assert.deepEqual(diagnostics[0].owned_node_ids, ["goal:demo:step:patch:input:ticket"]);
    assert.equal(diagnostics[0].declared_count, 1);
    assert.equal(diagnostics[0].owned_count, 1);
    assert.deepEqual(diagnostics[0].mismatched_indexes, [0]);
    assert.deepEqual(diagnostics[1].declared_values, ["ShellRun"]);
    assert.deepEqual(diagnostics[1].owned_values, ["FileWrite"]);
  });

  it("validates graph step input binding diagnostics", () => {
    const unboundDiagnostics = validateTestGraph({
      source: "synthetic.intent",
      nodes: [
        { id: "goal:demo", kind: "Goal", span: testSpan(1) },
        { id: "goal:demo:step:patch:input:input", kind: "Input", label: "input", span: testSpan(2), data: { scope: "step" } },
      ],
      edges: [],
    });
    const duplicateDiagnostics = validateTestGraph({
      source: "synthetic.intent",
      nodes: [
        { id: "goal:demo:input:a", kind: "Input", label: "a", span: testSpan(1), data: { scope: "goal" } },
        { id: "goal:demo:input:b", kind: "Input", label: "b", span: testSpan(2), data: { scope: "goal" } },
        { id: "goal:demo:step:patch:input:input", kind: "Input", label: "input", span: testSpan(3), data: { scope: "step" } },
      ],
      edges: [
        { from: "goal:demo:input:a", to: "goal:demo:step:patch:input:input", kind: "data", data: { parameter: "input", type: "Synthetic", sourceSpan: testSpan(1), targetSpan: testSpan(3) } },
        { from: "goal:demo:input:b", to: "goal:demo:step:patch:input:input", kind: "data", data: { parameter: "input", type: "Synthetic", sourceSpan: testSpan(2), targetSpan: testSpan(3) } },
      ],
    });

    assert.equal(unboundDiagnostics[0].code, "INTENT_GRAPH_INPUT_UNBOUND");
    assert.equal(unboundDiagnostics[0].incoming_data_edges, 0);
    assert.equal(duplicateDiagnostics[0].code, "INTENT_GRAPH_INPUT_UNBOUND");
    assert.equal(duplicateDiagnostics[0].incoming_data_edges, 2);
  });

  it("validates graph goal input supply diagnostics", () => {
    const diagnostics = validateTestGraph({
      source: "synthetic.intent",
      nodes: [
        { id: "goal:demo", kind: "Goal", label: "demo", span: testSpan(1) },
        { id: "goal:other", kind: "Goal", label: "other", span: testSpan(2) },
        { id: "goal:demo:input:missing", kind: "Input", label: "missing", span: testSpan(3), data: { scope: "goal" } },
        { id: "goal:demo:input:wrong", kind: "Input", label: "wrong", span: testSpan(4), data: { scope: "goal" } },
        { id: "goal:demo:input:duplicate", kind: "Input", label: "duplicate", span: testSpan(5), data: { scope: "goal" } },
        { id: "goal:demo:step:patch:input:input", kind: "Input", label: "input", span: testSpan(6), data: { scope: "step" } },
      ],
      edges: [
        { from: "goal:demo:input:wrong", to: "goal:other", kind: "supplies", data: { parameter: "wrong", type: "Synthetic", sourceSpan: testSpan(4), targetSpan: testSpan(4) } },
        { from: "goal:demo:input:duplicate", to: "goal:demo", kind: "supplies", data: { parameter: "duplicate", type: "Synthetic", sourceSpan: testSpan(5), targetSpan: testSpan(5) } },
        { from: "goal:demo:input:duplicate", to: "goal:demo", kind: "supplies", data: { parameter: "duplicate", type: "Synthetic", sourceSpan: testSpan(5), targetSpan: testSpan(5) } },
        { from: "goal:demo:step:patch:input:input", to: "goal:demo", kind: "supplies" },
      ],
    }).filter((diagnostic) => diagnostic.code === "INTENT_GRAPH_INPUT_SUPPLY_INVALID");

    assert.equal(diagnostics.length, 3);
    assert.equal(diagnostics[0].input_id, "goal:demo:input:missing");
    assert.equal(diagnostics[0].supply_edges, 0);
    assert.equal(diagnostics[0].owner_goal_supply_edges, 0);
    assert.equal(diagnostics[1].input_id, "goal:demo:input:wrong");
    assert.equal(diagnostics[1].supply_edges, 0);
    assert.equal(diagnostics[1].owner_goal_supply_edges, 0);
    assert.equal(diagnostics[2].input_id, "goal:demo:input:duplicate");
    assert.equal(diagnostics[2].supply_edges, 2);
    assert.equal(diagnostics[2].owner_goal_supply_edges, 2);
  });

  it("validates graph data edge shape diagnostics", () => {
    const diagnostics = validateTestGraph({
      source: "synthetic.intent",
      nodes: [
        { id: "goal:demo", kind: "Goal", span: testSpan(1) },
        { id: "goal:demo:input:a", kind: "Input", label: "a", span: testSpan(2), data: { scope: "goal" } },
        { id: "goal:demo:step:patch", kind: "Step", label: "patch", span: testSpan(3) },
        { id: "goal:demo:step:patch:input:input", kind: "Input", label: "input", span: testSpan(4), data: { scope: "step" } },
      ],
      edges: [
        { from: "goal:demo:input:a", to: "goal:demo", kind: "supplies", data: { parameter: "a", type: "Synthetic", sourceSpan: testSpan(2), targetSpan: testSpan(2) } },
        { from: "goal:demo", to: "goal:demo:step:patch:input:input", kind: "data", data: { parameter: "input", type: "Synthetic", sourceSpan: testSpan(1), targetSpan: testSpan(4) } },
        { from: "goal:demo:input:a", to: "goal:demo:step:patch", kind: "data", data: { parameter: "input", type: "Synthetic", sourceSpan: testSpan(2), targetSpan: testSpan(3) } },
      ],
    });

    assert.equal(diagnostics[0].code, "INTENT_GRAPH_DATA_ROLE_INVALID");
    assert.equal(diagnostics[0].from_kind, "Goal");
    assert.equal(diagnostics[0].to_kind, "Input");
    assert.equal(diagnostics[1].code, "INTENT_GRAPH_DATA_ROLE_INVALID");
    assert.equal(diagnostics[1].from_kind, "Input");
    assert.equal(diagnostics[1].to_kind, "Step");
    assert.equal(diagnostics[2].code, "INTENT_GRAPH_INPUT_UNBOUND");
  });

  it("validates graph data edge payload diagnostics", () => {
    const diagnostics = validateTestGraph({
      source: "synthetic.intent",
      nodes: [
        { id: "goal:demo:input:a", kind: "Input", label: "a", span: testSpan(1), data: { scope: "goal", type: "Finding" } },
        { id: "goal:demo:step:patch:input:input", kind: "Input", label: "input", span: testSpan(2), data: { scope: "step", type: "Finding" } },
      ],
      edges: [
        { from: "goal:demo:input:a", to: "goal:demo:step:patch:input:input", kind: "data" },
        { from: "goal:demo:input:a", to: "goal:demo:step:patch:input:input", kind: "data", data: { parameter: "", type: "Finding", sourceSpan: testSpan(1), targetSpan: testSpan(2) } },
        { from: "goal:demo:input:a", to: "goal:demo:step:patch:input:input", kind: "data", data: { parameter: "input", type: "", sourceSpan: testSpan(1), targetSpan: testSpan(2) } },
      ],
    }).filter((diagnostic) => diagnostic.code === "INTENT_GRAPH_EDGE_PAYLOAD_INVALID");

    assert.equal(diagnostics.length, 3);
    assert.equal(diagnostics[0].edge, "data");
    assert.equal(diagnostics[0].parameter_is_nonempty, false);
    assert.equal(diagnostics[0].type_is_nonempty, false);
    assert.equal(diagnostics[0].source_span_is_valid, false);
    assert.equal(diagnostics[0].target_span_is_valid, false);
    assert.equal(diagnostics[1].parameter_is_nonempty, false);
    assert.equal(diagnostics[1].type_is_nonempty, true);
    assert.equal(diagnostics[2].parameter_is_nonempty, true);
    assert.equal(diagnostics[2].type_is_nonempty, false);
    assert.equal(diagnostics[2].target_span_is_valid, true);
  });

  it("validates graph produces edge payload diagnostics", () => {
    const diagnostics = validateTestGraph({
      source: "synthetic.intent",
      nodes: [
        { id: "goal:demo:step:patch", kind: "Step", label: "patch", span: testSpan(1) },
        { id: "goal:demo:completion", kind: "Completion", label: "demo", span: testSpan(2) },
      ],
      edges: [
        { from: "goal:demo:step:patch", to: "goal:demo:completion", kind: "produces", data: { type: "", sourceSpan: testSpan(1), targetSpan: testSpan(2) } },
        { from: "goal:demo:step:patch", to: "goal:demo:completion", kind: "produces", data: { type: "Report", targetSpan: testSpan(2) } },
        { from: "goal:demo:step:patch", to: "goal:demo:completion", kind: "produces", data: { type: "Report", sourceSpan: testSpan(1) } },
      ],
    }).filter((diagnostic) => diagnostic.code === "INTENT_GRAPH_EDGE_PAYLOAD_INVALID");

    assert.equal(diagnostics.length, 3);
    assert.equal(diagnostics[0].edge, "produces");
    assert.equal(diagnostics[0].type_is_nonempty, false);
    assert.equal(diagnostics[0].source_span_is_valid, true);
    assert.equal(diagnostics[0].target_span_is_valid, true);
    assert.equal(diagnostics[1].type_is_nonempty, true);
    assert.equal(diagnostics[1].source_span_is_valid, false);
    assert.equal(diagnostics[2].type_is_nonempty, true);
    assert.equal(diagnostics[2].target_span_is_valid, false);
  });

  it("validates graph supplies edge payload diagnostics", () => {
    const diagnostics = validateTestGraph({
      source: "synthetic.intent",
      nodes: [
        { id: "goal:demo", kind: "Goal", label: "demo", span: testSpan(1) },
        { id: "goal:demo:input:ticket", kind: "Input", label: "ticket", span: testSpan(2), data: { scope: "goal", type: "Ticket" } },
      ],
      edges: [
        { from: "goal:demo:input:ticket", to: "goal:demo", kind: "supplies" },
        { from: "goal:demo:input:ticket", to: "goal:demo", kind: "supplies", data: { parameter: "", type: "Ticket", sourceSpan: testSpan(2), targetSpan: testSpan(2) } },
        { from: "goal:demo:input:ticket", to: "goal:demo", kind: "supplies", data: { parameter: "ticket", type: "", sourceSpan: testSpan(2), targetSpan: testSpan(2) } },
        { from: "goal:demo:input:ticket", to: "goal:demo", kind: "supplies", data: { parameter: "ticket", type: "Ticket", sourceSpan: testSpan(2) } },
      ],
    }).filter((diagnostic) => diagnostic.code === "INTENT_GRAPH_EDGE_PAYLOAD_INVALID");

    assert.equal(diagnostics.length, 4);
    assert.equal(diagnostics[0].edge, "supplies");
    assert.equal(diagnostics[0].parameter_is_nonempty, false);
    assert.equal(diagnostics[0].type_is_nonempty, false);
    assert.equal(diagnostics[0].source_span_is_valid, false);
    assert.equal(diagnostics[0].target_span_is_valid, false);
    assert.equal(diagnostics[1].parameter_is_nonempty, false);
    assert.equal(diagnostics[1].type_is_nonempty, true);
    assert.equal(diagnostics[2].parameter_is_nonempty, true);
    assert.equal(diagnostics[2].type_is_nonempty, false);
    assert.equal(diagnostics[3].parameter_is_nonempty, true);
    assert.equal(diagnostics[3].target_span_is_valid, false);
  });

  it("validates graph requires edge payload diagnostics", () => {
    const diagnostics = validateTestGraph({
      source: "synthetic.intent",
      nodes: [
        { id: "goal:demo:step:patch", kind: "Step", label: "patch", span: testSpan(1) },
        { id: "goal:demo:step:patch:input:input", kind: "Input", label: "input", span: testSpan(2), data: { scope: "step", type: "Finding" } },
        { id: "goal:demo:step:patch:requirement:0", kind: "Check", label: "reviewed", span: testSpan(3), data: { scope: "step", ownerStep: "patch", assertion: "Require", requirement: "reviewed" } },
      ],
      edges: [
        { from: "goal:demo:step:patch:input:input", to: "goal:demo:step:patch", kind: "requires", data: {} },
        { from: "goal:demo:step:patch:input:input", to: "goal:demo:step:patch", kind: "requires", data: { parameter: "", type: "Finding", targetSpan: testSpan(2) } },
        { from: "goal:demo:step:patch:input:input", to: "goal:demo:step:patch", kind: "requires", data: { parameter: "input", type: "", targetSpan: testSpan(2) } },
        { from: "goal:demo:step:patch:input:input", to: "goal:demo:step:patch", kind: "requires", data: { parameter: "input", type: "Finding" } },
        { from: "goal:demo:step:patch:requirement:0", to: "goal:demo:step:patch", kind: "requires", data: { requirement: "" } },
      ],
    }).filter((diagnostic) => diagnostic.code === "INTENT_GRAPH_EDGE_PAYLOAD_INVALID");

    assert.equal(diagnostics.length, 5);
    assert.equal(diagnostics[0].edge, "requires");
    assert.equal(diagnostics[0].parameter_is_nonempty, false);
    assert.equal(diagnostics[0].type_is_nonempty, false);
    assert.equal(diagnostics[0].target_span_is_valid, false);
    assert.equal(diagnostics[1].parameter_is_nonempty, false);
    assert.equal(diagnostics[1].type_is_nonempty, true);
    assert.equal(diagnostics[2].parameter_is_nonempty, true);
    assert.equal(diagnostics[2].type_is_nonempty, false);
    assert.equal(diagnostics[3].parameter_is_nonempty, true);
    assert.equal(diagnostics[3].type_is_nonempty, true);
    assert.equal(diagnostics[3].target_span_is_valid, false);
    assert.equal(diagnostics[4].requirement_is_nonempty, false);
  });

  it("validates graph check gate edge payload diagnostics", () => {
    const diagnostics = validateTestGraph({
      source: "synthetic.intent",
      nodes: [
        { id: "goal:demo", kind: "Goal", label: "demo", span: testSpan(1) },
        { id: "goal:demo:verify:0", kind: "Check", label: "ready", span: testSpan(2), data: { requirement: "ready", scope: "goal" } },
        { id: "goal:demo:completion", kind: "Completion", label: "demo", span: testSpan(3) },
      ],
      edges: [
        { from: "goal:demo:verify:0", to: "goal:demo", kind: "gates", data: {} },
        { from: "goal:demo:verify:0", to: "goal:demo", kind: "gates", data: { requirement: "", scope: "goal", sourceSpan: testSpan(2), targetSpan: testSpan(1) } },
        { from: "goal:demo:verify:0", to: "goal:demo:completion", kind: "verifies", data: { requirement: "ready", scope: "job", sourceSpan: testSpan(2), targetSpan: testSpan(3) } },
        { from: "goal:demo:verify:0", to: "goal:demo:completion", kind: "verifies", data: { requirement: "ready", scope: "goal", sourceSpan: testSpan(2) } },
      ],
    }).filter((diagnostic) => diagnostic.code === "INTENT_GRAPH_EDGE_PAYLOAD_INVALID");

    assert.equal(diagnostics.length, 4);
    assert.equal(diagnostics[0].edge, "gates");
    assert.equal(diagnostics[0].requirement_is_nonempty, false);
    assert.equal(diagnostics[0].scope_is_valid, false);
    assert.equal(diagnostics[0].source_span_is_valid, false);
    assert.equal(diagnostics[0].target_span_is_valid, false);
    assert.equal(diagnostics[1].requirement_is_nonempty, false);
    assert.equal(diagnostics[1].scope_is_valid, true);
    assert.equal(diagnostics[2].edge, "verifies");
    assert.equal(diagnostics[2].scope_is_valid, false);
    assert.equal(diagnostics[3].requirement_is_nonempty, true);
    assert.equal(diagnostics[3].target_span_is_valid, false);
  });

  it("validates graph step attachment edge payload diagnostics", () => {
    const diagnostics = validateTestGraph({
      source: "synthetic.intent",
      nodes: [
        { id: "goal:demo:step:patch", kind: "Step", label: "patch", span: testSpan(1) },
        { id: "goal:demo:step:patch:approval:0", kind: "Approval", label: "maintainer", span: testSpan(2) },
        { id: "goal:demo:step:patch:effect:0", kind: "Effect", label: "FileWrite", span: testSpan(3) },
        { id: "goal:demo:step:patch:timeout:0", kind: "Policy", label: "5m", span: testSpan(4), data: { policyKind: "timeout" } },
        { id: "goal:demo:step:patch:retry:0", kind: "Policy", label: "max 2", span: testSpan(5), data: { policyKind: "retry" } },
        { id: "goal:demo:step:patch:checkpoint:0", kind: "Checkpoint", label: "before", span: testSpan(6) },
      ],
      edges: [
        { from: "goal:demo:step:patch:approval:0", to: "goal:demo:step:patch", kind: "approves", data: {} },
        { from: "goal:demo:step:patch:approval:0", to: "goal:demo:step:patch:effect:0", kind: "approves", data: { approval: "" } },
        { from: "goal:demo:step:patch:timeout:0", to: "goal:demo:step:patch", kind: "timeouts", data: {} },
        { from: "goal:demo:step:patch:retry:0", to: "goal:demo:step:patch", kind: "retries", data: { policy: "" } },
        { from: "goal:demo:step:patch", to: "goal:demo:step:patch:checkpoint:0", kind: "checkpoints", data: {} },
      ],
    }).filter((diagnostic) => diagnostic.code === "INTENT_GRAPH_EDGE_PAYLOAD_INVALID");

    assert.equal(diagnostics.length, 5);
    assert.equal(diagnostics[0].edge, "approves");
    assert.equal(diagnostics[0].approval_is_nonempty, false);
    assert.equal(diagnostics[1].edge, "approves");
    assert.equal(diagnostics[1].approval_is_nonempty, false);
    assert.equal(diagnostics[2].edge, "timeouts");
    assert.equal(diagnostics[2].policy_is_nonempty, false);
    assert.equal(diagnostics[3].edge, "retries");
    assert.equal(diagnostics[3].policy_is_nonempty, false);
    assert.equal(diagnostics[4].edge, "checkpoints");
    assert.equal(diagnostics[4].checkpoint_is_nonempty, false);
  });

  it("validates graph step attachment typed edge diagnostics", () => {
    const diagnostics = validateTestGraph({
      source: "synthetic.intent",
      nodes: [
        { id: "goal:demo:step:patch", kind: "Step", label: "patch", span: testSpan(1) },
        { id: "goal:demo:step:other", kind: "Step", label: "other", span: testSpan(2) },
        { id: "goal:demo:step:patch:approval:0", kind: "Approval", label: "maintainer", span: testSpan(3), data: { approval: "maintainer" } },
        { id: "goal:demo:step:other:effect:0", kind: "Effect", label: "FileWrite", span: testSpan(4) },
        { id: "goal:demo:step:patch:timeout:0", kind: "Policy", label: "5m", span: testSpan(5), data: { policyKind: "timeout", policy: "5m" } },
        { id: "goal:demo:step:patch:retry:0", kind: "Policy", label: "max 2", span: testSpan(6), data: { policyKind: "retry", policy: "max 2" } },
        { id: "goal:demo:step:other:checkpoint:0", kind: "Checkpoint", label: "before", span: testSpan(7), data: { checkpoint: "before" } },
      ],
      edges: [
        { from: "goal:demo:step:patch:approval:0", to: "goal:demo:step:other:effect:0", kind: "approves", data: { approval: "owner" } },
        { from: "goal:demo:step:patch:timeout:0", to: "goal:demo:step:patch", kind: "timeouts", data: { policy: "10m" } },
        { from: "goal:demo:step:patch:retry:0", to: "goal:demo:step:patch", kind: "retries", data: { policy: "max 1" } },
        { from: "goal:demo:step:patch", to: "goal:demo:step:other:checkpoint:0", kind: "checkpoints", data: { checkpoint: "after" } },
      ],
    }).filter((diagnostic) => diagnostic.code === "INTENT_GRAPH_TYPED_EDGE_INVALID");

    assert.equal(diagnostics.length, 4);
    assert.equal(diagnostics[0].edge, "approves");
    assert.deepEqual(diagnostics[0].checks.map((check) => [check.name, check.ok]), [
      ["owner_step_matches_target", false],
      ["approval_matches_source", false],
    ]);
    assert.equal(diagnostics[1].edge, "timeouts");
    assert.deepEqual(diagnostics[1].checks.map((check) => [check.name, check.ok]), [
      ["owner_step_matches_target", true],
      ["policy_kind_matches_edge", true],
      ["policy_matches_source", false],
    ]);
    assert.equal(diagnostics[2].edge, "retries");
    assert.equal(diagnostics[2].checks[2].name, "policy_matches_source");
    assert.equal(diagnostics[2].checks[2].ok, false);
    assert.equal(diagnostics[3].edge, "checkpoints");
    assert.deepEqual(diagnostics[3].checks.map((check) => [check.name, check.ok]), [
      ["owner_step_matches_source", false],
      ["checkpoint_matches_target", false],
    ]);
  });

  it("validates graph memory access edge payload diagnostics", () => {
    const diagnostics = validateTestGraph({
      source: "synthetic.intent",
      nodes: [
        { id: "goal:demo:memory:0", kind: "Memory", label: "session", span: testSpan(1) },
        { id: "goal:demo:step:patch", kind: "Step", label: "patch", span: testSpan(2) },
      ],
      edges: [
        { from: "goal:demo:memory:0", to: "goal:demo:step:patch", kind: "reads", data: {} },
        { from: "goal:demo:step:patch", to: "goal:demo:memory:0", kind: "writes", data: { access: "write", memory: "", target: "session.evidence", sourceSpan: testSpan(2), targetSpan: testSpan(1) } },
        { from: "goal:demo:memory:0", to: "goal:demo:step:patch", kind: "cites", data: { access: "cite", memory: "session", target: "", sourceSpan: testSpan(1), targetSpan: testSpan(2) } },
        { from: "goal:demo:memory:0", to: "goal:demo:step:patch", kind: "reads", data: { access: "observe", memory: "session", target: "session.evidence", sourceSpan: testSpan(1), targetSpan: testSpan(2) } },
        { from: "goal:demo:memory:0", to: "goal:demo:step:patch", kind: "reads", data: { access: "read", memory: "session", target: "session.evidence" } },
      ],
    }).filter((diagnostic) => diagnostic.code === "INTENT_GRAPH_EDGE_PAYLOAD_INVALID");

    assert.equal(diagnostics.length, 5);
    assert.equal(diagnostics[0].edge, "reads");
    assert.equal(diagnostics[0].access_is_valid, false);
    assert.equal(diagnostics[0].memory_is_nonempty, false);
    assert.equal(diagnostics[0].target_is_nonempty, false);
    assert.equal(diagnostics[1].memory_is_nonempty, false);
    assert.equal(diagnostics[2].target_is_nonempty, false);
    assert.equal(diagnostics[3].access_is_valid, false);
    assert.equal(diagnostics[4].source_span_is_valid, false);
    assert.equal(diagnostics[4].target_span_is_valid, false);
  });

  it("validates graph check gate diagnostics", () => {
    const diagnostics = validateTestGraph({
      source: "synthetic.intent",
      nodes: [
        { id: "goal:demo", kind: "Goal", label: "demo", span: testSpan(1) },
        { id: "goal:demo:step:patch", kind: "Step", label: "patch", span: testSpan(2) },
        { id: "goal:demo:verify:0", kind: "Check", label: "ok", span: testSpan(3) },
        { id: "goal:demo:verify:1", kind: "Check", label: "bad target", span: testSpan(4) },
        { id: "goal:demo:step:patch:requirement:0", kind: "Check", label: "ready", span: testSpan(5), data: { scope: "step", ownerStep: "patch", assertion: "Require" } },
        { id: "goal:demo:completion", kind: "Completion", label: "demo", span: testSpan(6) },
        { id: "goal:other:completion", kind: "Completion", label: "other", span: testSpan(7) },
      ],
      edges: [
        { from: "goal:demo:verify:0", to: "goal:demo:completion", kind: "verifies" },
        { from: "goal:demo:verify:1", to: "goal:demo", kind: "gates" },
        { from: "goal:demo:verify:1", to: "goal:other:completion", kind: "verifies" },
        { from: "goal:demo:step:patch:requirement:0", to: "goal:demo", kind: "gates" },
        { from: "goal:demo:step:patch:requirement:0", to: "goal:demo:step:patch", kind: "requires" },
        { from: "goal:demo:step:patch:requirement:0", to: "goal:demo:completion", kind: "verifies" },
      ],
    }).filter((diagnostic) => diagnostic.code === "INTENT_GRAPH_CHECK_GATE_INVALID");

    assert.equal(diagnostics.length, 3);
    assert.equal(diagnostics[0].check_id, "goal:demo:verify:0");
    assert.equal(diagnostics[0].owner_goal_gate_edges, 0);
    assert.equal(diagnostics[0].owner_completion_verify_edges, 1);
    assert.equal(diagnostics[1].check_id, "goal:demo:verify:1");
    assert.equal(diagnostics[1].owner_goal_gate_edges, 1);
    assert.equal(diagnostics[1].owner_completion_verify_edges, 0);
    assert.equal(diagnostics[2].check_id, "goal:demo:step:patch:requirement:0");
    assert.equal(diagnostics[2].scope, "step");
    assert.equal(diagnostics[2].verify_edges, 1);
  });

  it("validates graph authorization diagnostics", () => {
    const diagnostics = validateTestGraph({
      source: "synthetic.intent",
      nodes: [
        { id: "goal:demo", kind: "Goal", label: "demo", span: testSpan(1) },
        { id: "goal:demo:capability:0", kind: "Capability", label: "file", span: testSpan(2) },
        { id: "goal:demo:step:patch", kind: "Step", label: "patch", span: testSpan(3) },
        { id: "goal:demo:step:patch:effect:0", kind: "Effect", label: "FileWrite", span: testSpan(3) },
        { id: "goal:demo:verify:0", kind: "Check", label: "shell(\"npm test\")", span: testSpan(4), data: { effect: { family: "shell", action: "run" } } },
        { id: "goal:demo:completion", kind: "Completion", label: "demo", span: testSpan(5) },
      ],
      edges: [
        { from: "goal:demo:capability:0", to: "goal:demo", kind: "authorizes" },
        { from: "goal:demo", to: "goal:demo:step:patch", kind: "plans" },
        { from: "goal:demo:step:patch", to: "goal:demo:step:patch:effect:0", kind: "requests" },
        { from: "goal:demo", to: "goal:demo:step:patch:effect:0", kind: "authorizes" },
        { from: "goal:demo", to: "goal:demo:completion", kind: "completes" },
        { from: "goal:demo:step:patch", to: "goal:demo:completion", kind: "produces", data: { type: "Synthetic", sourceSpan: testSpan(1), targetSpan: testSpan(1) } },
        { from: "goal:demo:verify:0", to: "goal:demo", kind: "gates" },
        { from: "goal:demo:verify:0", to: "goal:demo:completion", kind: "verifies" },
      ],
    }).filter((diagnostic) => diagnostic.code === "INTENT_GRAPH_AUTHORIZATION_INVALID");

    assert.equal(diagnostics.length, 2);
    assert.equal(diagnostics[0].target_id, "goal:demo:step:patch:effect:0");
    assert.equal(diagnostics[0].authorizes_edges, 0);
    assert.equal(diagnostics[0].capability_authorizes_edges, 0);
    assert.equal(diagnostics[1].target_id, "goal:demo:verify:0");
    assert.equal(diagnostics[1].authorizes_edges, 0);
  });

  it("validates graph authorization grant diagnostics", () => {
    const diagnostics = validateTestGraph({
      source: "synthetic.intent",
      nodes: [
        { id: "goal:demo", kind: "Goal", label: "demo", span: testSpan(1) },
        { id: "goal:demo:capability:file", kind: "Capability", label: "file", span: testSpan(2), data: { family: "file", grants: [testGrant("write", "path", "./src/**", 2)] } },
        { id: "goal:demo:capability:shell", kind: "Capability", label: "shell", span: testSpan(3), data: { family: "shell", grants: [testGrant("run", "command", "npm test", 3)] } },
        { id: "goal:demo:capability:web", kind: "Capability", label: "web", span: testSpan(4), data: { family: "web", grants: [testGrant("read", "domain", "example.com", 4)] } },
        { id: "goal:demo:capability:documents", kind: "Capability", label: "documents", span: testSpan(5), data: { family: "file", grants: [testGrant("read", "path", "docs/**", 5)] } },
        {
          id: "goal:demo:step:patch:effect:0",
          kind: "Effect",
          label: "FileWrite",
          span: testSpan(6),
          data: { family: "file", action: "write", args: { path: "outside/file.txt" }, argKinds: { path: "string" }, argSpans: { path: testSpan(6) } },
        },
        {
          id: "goal:demo:verify:0",
          kind: "Check",
          label: "shell(\"npm run build\")",
          span: testSpan(7),
          data: { effect: { family: "shell", action: "run", args: { command: "npm run build" }, argKinds: { command: "string" }, argSpans: { command: testSpan(7) } } },
        },
        {
          id: "goal:demo:context:web",
          kind: "Context",
          label: "web",
          span: testSpan(8),
          data: { source: "web", args: { url: "https://evil.example/path" }, argKinds: { url: "string" }, argSpans: { url: testSpan(8) }, expression: "web(url: \"https://evil.example/path\")" },
        },
        {
          id: "goal:demo:context:documents",
          kind: "Context",
          label: "documents",
          span: testSpan(9),
          data: { source: "documents", args: { path: "secrets/spec.md" }, argKinds: { path: "string" }, argSpans: { path: testSpan(9) }, expression: "documents(path: \"secrets/spec.md\")" },
        },
      ],
      edges: [
        { from: "goal:demo:capability:file", to: "goal:demo", kind: "authorizes" },
        { from: "goal:demo:capability:shell", to: "goal:demo", kind: "authorizes" },
        { from: "goal:demo:capability:web", to: "goal:demo", kind: "authorizes" },
        { from: "goal:demo:capability:documents", to: "goal:demo", kind: "authorizes" },
        { from: "goal:demo:capability:file", to: "goal:demo:step:patch:effect:0", kind: "authorizes" },
        { from: "goal:demo:capability:shell", to: "goal:demo:verify:0", kind: "authorizes" },
        { from: "goal:demo:capability:web", to: "goal:demo:context:web", kind: "authorizes" },
        { from: "goal:demo:capability:documents", to: "goal:demo:context:documents", kind: "authorizes" },
      ],
    }).filter((diagnostic) => diagnostic.code === "INTENT_GRAPH_AUTHORIZATION_GRANT_INVALID");

    assert.equal(diagnostics.length, 4);
    assert.equal(diagnostics[0].target_id, "goal:demo:step:patch:effect:0");
    assert.deepEqual(diagnostics[0].invalid_authorizations[0], {
      from: "goal:demo:capability:file",
      to: "goal:demo:step:patch:effect:0",
      reason: "grant_mismatch",
      capability_family: "file",
      target_family: "file",
      target_action: "write",
      argument: "path",
      value: "outside/file.txt",
      allowed: ["./src/**"],
    });
    assert.equal(diagnostics[1].target_id, "goal:demo:verify:0");
    assert.equal(diagnostics[1].invalid_authorizations[0].argument, "command");
    assert.equal(diagnostics[1].invalid_authorizations[0].value, "npm run build");
    assert.deepEqual(diagnostics[1].invalid_authorizations[0].allowed, ["npm test"]);
    assert.equal(diagnostics[2].target_id, "goal:demo:context:web");
    assert.equal(diagnostics[2].invalid_authorizations[0].argument, "domain");
    assert.equal(diagnostics[2].invalid_authorizations[0].value, "evil.example");
    assert.deepEqual(diagnostics[2].invalid_authorizations[0].allowed, ["example.com"]);
    assert.equal(diagnostics[3].target_id, "goal:demo:context:documents");
    assert.equal(diagnostics[3].invalid_authorizations[0].argument, "path");
    assert.equal(diagnostics[3].invalid_authorizations[0].value, "secrets/spec.md");
    assert.deepEqual(diagnostics[3].invalid_authorizations[0].allowed, ["docs/**"]);
  });

  it("rejects stale effect authorization contract edge references", () => {
    const diagnostics = validateTestGraph({
      source: "synthetic.intent",
      nodes: [
        { id: "goal:demo", kind: "Goal", label: "demo", span: testSpan(1) },
        {
          id: "goal:demo:capability:file",
          kind: "Capability",
          label: "file",
          span: testSpan(2),
          data: {
            family: "file",
            grants: [{
              ...testGrant("write", "path", "./src/**", 2),
              contractId: "intent.effect.file.write.v0",
              contractArgument: "path",
            }],
          },
        },
        {
          id: "goal:demo:step:patch:effect:0",
          kind: "Effect",
          label: "WriteFile",
          span: testSpan(3),
          data: {
            family: "file",
            action: "write",
            contractId: "intent.effect.file.write.v0",
            contractArguments: { path: "_0" },
            args: { _0: "./src/app.ts" },
            argKinds: { _0: "string" },
            argSpans: { _0: testSpan(3) },
          },
        },
      ],
      edges: [
        { from: "goal:demo:capability:file", to: "goal:demo", kind: "authorizes" },
        {
          from: "goal:demo:capability:file",
          to: "goal:demo:step:patch:effect:0",
          kind: "authorizes",
          data: {
            contractId: "intent.effect.file.write.v0",
            contractArguments: { path: "_0" },
            grants: [{ argument: "path", sourceArgument: "path", value: "./src/app.ts" }],
          },
        },
      ],
    }).filter((diagnostic) => diagnostic.code === "INTENT_GRAPH_AUTHORIZATION_GRANT_INVALID");

    assert.equal(diagnostics.length, 1);
    assert.equal(diagnostics[0].target_id, "goal:demo:step:patch:effect:0");
    assert.equal(diagnostics[0].invalid_authorizations[0].reason, "edge_argument_mismatch");
    assert.equal(diagnostics[0].invalid_authorizations[0].argument, "path");
    assert.equal(diagnostics[0].invalid_authorizations[0].value, "path");
    assert.deepEqual(diagnostics[0].invalid_authorizations[0].allowed, ["_0"]);
  });

  it("rejects stale context authorization contract edge references", () => {
    const diagnostics = validateTestGraph({
      source: "synthetic.intent",
      nodes: [
        { id: "goal:demo", kind: "Goal", label: "demo", span: testSpan(1) },
        {
          id: "goal:demo:capability:web",
          kind: "Capability",
          label: "web",
          span: testSpan(2),
          data: {
            family: "web",
            grants: [{
              ...testGrant("read", "domain", "example.com", 2),
              contractId: "intent.effect.web.read.v0",
              contractArgument: "domain",
            }],
          },
        },
        {
          id: "goal:demo:context:web",
          kind: "Context",
          label: "web",
          span: testSpan(3),
          data: {
            source: "web",
            expression: "web(url: \"https://example.com/context\")",
            contractId: "intent.effect.web.read.v0",
            contractArguments: { domain: "url" },
            args: { url: "https://example.com/context" },
            argKinds: { url: "string" },
            argSpans: { url: testSpan(3) },
          },
        },
      ],
      edges: [
        { from: "goal:demo:capability:web", to: "goal:demo", kind: "authorizes" },
        {
          from: "goal:demo:capability:web",
          to: "goal:demo:context:web",
          kind: "authorizes",
          data: {
            contractId: "intent.effect.web.read.v0",
            contractArguments: { domain: "url" },
            grants: [{ argument: "domain", sourceArgument: "domain", value: "example.com" }],
          },
        },
      ],
    }).filter((diagnostic) => diagnostic.code === "INTENT_GRAPH_AUTHORIZATION_GRANT_INVALID");

    assert.equal(diagnostics.length, 1);
    assert.equal(diagnostics[0].target_id, "goal:demo:context:web");
    assert.equal(diagnostics[0].invalid_authorizations[0].reason, "edge_argument_mismatch");
    assert.equal(diagnostics[0].invalid_authorizations[0].argument, "domain");
    assert.equal(diagnostics[0].invalid_authorizations[0].value, "domain");
    assert.deepEqual(diagnostics[0].invalid_authorizations[0].allowed, ["url"]);
  });

  it("rejects stale authorization edge grant metadata", () => {
    const expectedGrant = testAuthorizationGrant("path", "_0", "./src/app.ts", "write", "path", "./src/**", 2);
    const diagnostics = validateTestGraph({
      source: "synthetic.intent",
      nodes: [
        { id: "goal:demo", kind: "Goal", label: "demo", span: testSpan(1) },
        {
          id: "goal:demo:capability:file",
          kind: "Capability",
          label: "file",
          span: testSpan(2),
          data: {
            family: "file",
            grants: [{
              ...testGrant("write", "path", "./src/**", 2),
              contractId: "intent.effect.file.write.v0",
              contractArgument: "path",
            }],
          },
        },
        {
          id: "goal:demo:step:patch:effect:0",
          kind: "Effect",
          label: "WriteFile",
          span: testSpan(3),
          data: {
            family: "file",
            action: "write",
            contractId: "intent.effect.file.write.v0",
            contractArguments: { path: "_0" },
            args: { _0: "./src/app.ts" },
            argKinds: { _0: "string" },
            argSpans: { _0: testSpan(3) },
          },
        },
      ],
      edges: [
        { from: "goal:demo:capability:file", to: "goal:demo", kind: "authorizes" },
        {
          from: "goal:demo:capability:file",
          to: "goal:demo:step:patch:effect:0",
          kind: "authorizes",
          data: {
            contractId: "intent.effect.file.write.v0",
            contractArguments: { path: "_0" },
            grants: [{ ...expectedGrant, grantAction: "read" }],
          },
        },
      ],
    }).filter((diagnostic) => diagnostic.code === "INTENT_GRAPH_AUTHORIZATION_GRANT_INVALID");

    assert.equal(diagnostics.length, 1);
    assert.equal(diagnostics[0].target_id, "goal:demo:step:patch:effect:0");
    assert.equal(diagnostics[0].invalid_authorizations[0].reason, "edge_grant_mismatch");
    assert.equal(diagnostics[0].invalid_authorizations[0].argument, "path");
    assert.deepEqual(diagnostics[0].invalid_authorizations[0].value, { ...expectedGrant, grantAction: "read" });
    assert.deepEqual(diagnostics[0].invalid_authorizations[0].allowed, [expectedGrant]);
  });

  it("rejects stale context authorization edge grant metadata", () => {
    const expectedGrant = testAuthorizationGrant("domain", "url", "example.com", "read", "domain", "example.com", 2);
    const diagnostics = validateTestGraph({
      source: "synthetic.intent",
      nodes: [
        { id: "goal:demo", kind: "Goal", label: "demo", span: testSpan(1) },
        {
          id: "goal:demo:capability:web",
          kind: "Capability",
          label: "web",
          span: testSpan(2),
          data: {
            family: "web",
            grants: [{
              ...testGrant("read", "domain", "example.com", 2),
              contractId: "intent.effect.web.read.v0",
              contractArgument: "domain",
            }],
          },
        },
        {
          id: "goal:demo:context:web",
          kind: "Context",
          label: "web",
          span: testSpan(3),
          data: {
            source: "web",
            expression: "web(url: \"https://example.com/context\")",
            contractId: "intent.effect.web.read.v0",
            contractArguments: { domain: "url" },
            args: { url: "https://example.com/context" },
            argKinds: { url: "string" },
            argSpans: { url: testSpan(3) },
          },
        },
      ],
      edges: [
        { from: "goal:demo:capability:web", to: "goal:demo", kind: "authorizes" },
        {
          from: "goal:demo:capability:web",
          to: "goal:demo:context:web",
          kind: "authorizes",
          data: {
            contractId: "intent.effect.web.read.v0",
            contractArguments: { domain: "url" },
            grants: [{ ...expectedGrant, grantValue: "evil.com" }],
          },
        },
      ],
    }).filter((diagnostic) => diagnostic.code === "INTENT_GRAPH_AUTHORIZATION_GRANT_INVALID");

    assert.equal(diagnostics.length, 1);
    assert.equal(diagnostics[0].target_id, "goal:demo:context:web");
    assert.equal(diagnostics[0].invalid_authorizations[0].reason, "edge_grant_mismatch");
    assert.equal(diagnostics[0].invalid_authorizations[0].argument, "domain");
    assert.deepEqual(diagnostics[0].invalid_authorizations[0].value, { ...expectedGrant, grantValue: "evil.com" });
    assert.deepEqual(diagnostics[0].invalid_authorizations[0].allowed, [expectedGrant]);
  });

  it("validates graph context authorization diagnostics", () => {
    const diagnostics = validateTestGraph({
      source: "synthetic.intent",
      nodes: [
        { id: "goal:demo", kind: "Goal", label: "demo", span: testSpan(1) },
        { id: "goal:demo:capability:0", kind: "Capability", label: "web", span: testSpan(2) },
        { id: "goal:demo:context:repo", kind: "Context", label: "repo", span: testSpan(3), data: { source: "repo" } },
        { id: "goal:demo:context:web", kind: "Context", label: "web", span: testSpan(4), data: { source: "web" } },
        { id: "goal:demo:context:documents", kind: "Context", label: "documents", span: testSpan(5), data: { source: "documents" } },
        { id: "goal:demo:context:authorized", kind: "Context", label: "authorized", span: testSpan(6), data: { source: "web" } },
      ],
      edges: [
        { from: "goal:demo", to: "goal:demo:context:repo", kind: "informs" },
        { from: "goal:demo", to: "goal:demo:context:web", kind: "informs" },
        { from: "goal:demo", to: "goal:demo:context:documents", kind: "authorizes" },
        { from: "goal:demo:capability:0", to: "goal:demo", kind: "authorizes" },
        { from: "goal:demo:capability:0", to: "goal:demo:context:authorized", kind: "authorizes" },
        { from: "goal:demo:context:documents", to: "goal:demo", kind: "informs" },
        { from: "goal:demo:context:authorized", to: "goal:demo", kind: "informs" },
      ],
    }).filter((diagnostic) => diagnostic.code === "INTENT_GRAPH_AUTHORIZATION_INVALID");

    assert.equal(diagnostics.length, 2);
    assert.equal(diagnostics[0].target_id, "goal:demo:context:web");
    assert.equal(diagnostics[0].target_kind, "Context");
    assert.equal(diagnostics[0].authorizes_edges, 0);
    assert.equal(diagnostics[1].target_id, "goal:demo:context:documents");
    assert.equal(diagnostics[1].authorizes_edges, 0);
    assert.equal(diagnostics[1].capability_authorizes_edges, 0);
  });

  it("validates graph capability ownership authorization diagnostics", () => {
    const diagnostics = validateTestGraph({
      source: "synthetic.intent",
      nodes: [
        { id: "goal:demo", kind: "Goal", label: "demo", span: testSpan(1) },
        { id: "goal:other", kind: "Goal", label: "other", span: testSpan(2) },
        { id: "goal:demo:capability:missing", kind: "Capability", label: "missing", span: testSpan(3) },
        { id: "goal:demo:capability:wrong", kind: "Capability", label: "wrong", span: testSpan(4) },
        { id: "goal:demo:capability:duplicate", kind: "Capability", label: "duplicate", span: testSpan(5) },
        { id: "goal:demo:capability:valid", kind: "Capability", label: "valid", span: testSpan(6) },
        { id: "goal:demo:step:patch", kind: "Step", label: "patch", span: testSpan(7) },
        { id: "goal:demo:step:patch:effect:0", kind: "Effect", label: "FileWrite", span: testSpan(8) },
      ],
      edges: [
        { from: "goal:demo:capability:wrong", to: "goal:other", kind: "authorizes" },
        { from: "goal:demo:capability:duplicate", to: "goal:demo", kind: "authorizes" },
        { from: "goal:demo:capability:duplicate", to: "goal:demo", kind: "authorizes" },
        { from: "goal:demo:capability:valid", to: "goal:demo", kind: "authorizes" },
        { from: "goal:demo:capability:valid", to: "goal:demo:step:patch:effect:0", kind: "authorizes" },
      ],
    }).filter((diagnostic) => diagnostic.code === "INTENT_GRAPH_CAPABILITY_AUTHORIZES_INVALID");

    assert.equal(diagnostics.length, 3);
    assert.equal(diagnostics[0].capability_id, "goal:demo:capability:missing");
    assert.equal(diagnostics[0].authorizes_edges, 0);
    assert.equal(diagnostics[0].owner_goal_authorizes_edges, 0);
    assert.equal(diagnostics[1].capability_id, "goal:demo:capability:wrong");
    assert.equal(diagnostics[1].authorizes_edges, 1);
    assert.equal(diagnostics[1].owner_goal_authorizes_edges, 0);
    assert.equal(diagnostics[1].wrong_goal_authorizes_edges, 1);
    assert.equal(diagnostics[2].capability_id, "goal:demo:capability:duplicate");
    assert.equal(diagnostics[2].authorizes_edges, 2);
    assert.equal(diagnostics[2].owner_goal_authorizes_edges, 2);
  });

  it("validates graph capability ownership authorization metadata diagnostics", () => {
    const capabilitySpan = testSpan(2);
    const goalSpan = testSpan(1);
    const diagnostics = validateTestGraph({
      source: "synthetic.intent",
      nodes: [
        { id: "goal:demo", kind: "Goal", label: "demo", span: goalSpan },
        {
          id: "goal:demo:capability:0",
          kind: "Capability",
          label: "file",
          span: capabilitySpan,
          data: { family: "file", action: "write", grants: [], approvalPolicy: "required" },
        },
      ],
      edges: [
        {
          from: "goal:demo:capability:0",
          to: "goal:demo",
          kind: "authorizes",
          data: {
            capability: "file",
            family: "file",
            action: "write",
            approvalPolicy: "none",
            goal: "demo",
            sourceSpan: capabilitySpan,
            targetSpan: goalSpan,
          },
        },
      ],
    }).filter((diagnostic) => diagnostic.code === "INTENT_GRAPH_CAPABILITY_AUTHORIZES_INVALID");

    assert.equal(diagnostics.length, 1);
    assert.equal(diagnostics[0].data_is_object, true);
    assert.equal(diagnostics[0].capability_matches_source, true);
    assert.equal(diagnostics[0].family_matches_source, true);
    assert.equal(diagnostics[0].action_matches_source, true);
    assert.equal(diagnostics[0].approval_policy_matches_source, false);
    assert.equal(diagnostics[0].goal_matches_target, true);
    assert.equal(diagnostics[0].source_span_matches_capability, true);
    assert.equal(diagnostics[0].target_span_matches_goal, true);
  });

  it("validates graph context informs diagnostics", () => {
    const diagnostics = validateTestGraph({
      source: "synthetic.intent",
      nodes: [
        { id: "goal:demo", kind: "Goal", label: "demo", span: testSpan(1) },
        { id: "goal:other", kind: "Goal", label: "other", span: testSpan(2) },
        { id: "goal:demo:context:missing", kind: "Context", label: "missing", span: testSpan(3) },
        { id: "goal:demo:context:wrong", kind: "Context", label: "wrong", span: testSpan(4) },
        { id: "goal:demo:context:duplicate", kind: "Context", label: "duplicate", span: testSpan(5) },
      ],
      edges: [
        { from: "goal:demo:context:wrong", to: "goal:other", kind: "informs" },
        { from: "goal:demo:context:duplicate", to: "goal:demo", kind: "informs" },
        { from: "goal:demo:context:duplicate", to: "goal:other", kind: "informs" },
      ],
    }).filter((diagnostic) => diagnostic.code === "INTENT_GRAPH_CONTEXT_INFORMS_INVALID");

    assert.equal(diagnostics.length, 3);
    assert.equal(diagnostics[0].context_id, "goal:demo:context:missing");
    assert.equal(diagnostics[0].informs_edges, 0);
    assert.equal(diagnostics[0].owner_goal_informs_edges, 0);
    assert.equal(diagnostics[1].context_id, "goal:demo:context:wrong");
    assert.equal(diagnostics[1].informs_edges, 1);
    assert.equal(diagnostics[1].owner_goal_informs_edges, 0);
    assert.equal(diagnostics[2].context_id, "goal:demo:context:duplicate");
    assert.equal(diagnostics[2].informs_edges, 2);
    assert.equal(diagnostics[2].owner_goal_informs_edges, 1);
  });

  it("validates graph context informs metadata diagnostics", () => {
    const contextSpan = testSpan(2);
    const goalSpan = testSpan(1);
    const diagnostics = validateTestGraph({
      source: "synthetic.intent",
      nodes: [
        { id: "goal:demo", kind: "Goal", label: "demo", span: goalSpan },
        {
          id: "goal:demo:context:web",
          kind: "Context",
          label: "web",
          span: contextSpan,
          data: {
            source: "web",
            expression: "web(url: \"https://example.com/context\")",
            contractId: "intent.effect.web.read.v0",
            contractArguments: { domain: "url" },
            args: { url: "https://example.com/context" },
            argKinds: { url: "string" },
            argSpans: { url: contextSpan },
            trust: { zone: "untrusted", source: "external_context" },
          },
        },
      ],
      edges: [
        {
          from: "goal:demo:context:web",
          to: "goal:demo",
          kind: "informs",
          data: {
            source: "documents",
            expression: "web(url: \"https://example.com/context\")",
            contractId: "intent.effect.web.read.v0",
            contractArguments: { domain: "url" },
            args: { url: "https://example.com/context" },
            argKinds: { url: "string" },
            argSpans: { url: contextSpan },
            trust: { zone: "untrusted", source: "external_context" },
            sourceSpan: contextSpan,
            targetSpan: goalSpan,
          },
        },
      ],
    }).filter((diagnostic) => diagnostic.code === "INTENT_GRAPH_CONTEXT_INFORMS_INVALID");

    assert.equal(diagnostics.length, 1);
    assert.equal(diagnostics[0].context_id, "goal:demo:context:web");
    assert.equal(diagnostics[0].data_is_object, true);
    assert.equal(diagnostics[0].source_matches_context, false);
    assert.equal(diagnostics[0].expression_matches_context, true);
    assert.equal(diagnostics[0].trust_matches_context, true);
    assert.equal(diagnostics[0].contract_arguments_match_context, true);
    assert.equal(diagnostics[0].source_span_matches_context, true);
    assert.equal(diagnostics[0].target_span_matches_goal, true);
  });

  it("validates graph effect request diagnostics", () => {
    const missingDiagnostics = validateTestGraph({
      source: "synthetic.intent",
      nodes: [
        { id: "goal:demo", kind: "Goal", label: "demo", span: testSpan(1) },
        { id: "goal:demo:step:patch", kind: "Step", label: "patch", span: testSpan(2) },
        { id: "goal:demo:capability:0", kind: "Capability", label: "file", span: testSpan(3) },
        { id: "goal:demo:step:patch:effect:0", kind: "Effect", label: "FileWrite", span: testSpan(4) },
        { id: "goal:demo:verify:0", kind: "Check", label: "ok", span: testSpan(5) },
        { id: "goal:demo:completion", kind: "Completion", label: "demo", span: testSpan(6) },
      ],
      edges: [
        { from: "goal:demo:capability:0", to: "goal:demo", kind: "authorizes" },
        { from: "goal:demo", to: "goal:demo:step:patch", kind: "plans" },
        { from: "goal:demo:capability:0", to: "goal:demo:step:patch:effect:0", kind: "authorizes" },
        { from: "goal:demo", to: "goal:demo:completion", kind: "completes" },
        { from: "goal:demo:step:patch", to: "goal:demo:completion", kind: "produces" },
        { from: "goal:demo:verify:0", to: "goal:demo", kind: "gates" },
        { from: "goal:demo:verify:0", to: "goal:demo:completion", kind: "verifies" },
      ],
    });
    const wrongSourceDiagnostics = validateTestGraph({
      source: "synthetic.intent",
      nodes: [
        { id: "goal:demo", kind: "Goal", label: "demo", span: testSpan(1) },
        { id: "goal:demo:step:patch", kind: "Step", label: "patch", span: testSpan(2) },
        { id: "goal:demo:capability:0", kind: "Capability", label: "file", span: testSpan(3) },
        { id: "goal:demo:step:patch:effect:0", kind: "Effect", label: "FileWrite", span: testSpan(4) },
        { id: "goal:demo:verify:0", kind: "Check", label: "ok", span: testSpan(5) },
        { id: "goal:demo:completion", kind: "Completion", label: "demo", span: testSpan(6) },
      ],
      edges: [
        { from: "goal:demo:capability:0", to: "goal:demo", kind: "authorizes" },
        { from: "goal:demo", to: "goal:demo:step:patch", kind: "plans" },
        { from: "goal:demo", to: "goal:demo:step:patch:effect:0", kind: "requests" },
        { from: "goal:demo:capability:0", to: "goal:demo:step:patch:effect:0", kind: "authorizes" },
        { from: "goal:demo", to: "goal:demo:completion", kind: "completes" },
        { from: "goal:demo:step:patch", to: "goal:demo:completion", kind: "produces" },
        { from: "goal:demo:verify:0", to: "goal:demo", kind: "gates" },
        { from: "goal:demo:verify:0", to: "goal:demo:completion", kind: "verifies" },
      ],
    });

    assert.equal(missingDiagnostics.length, 1);
    assert.equal(missingDiagnostics[0].code, "INTENT_GRAPH_EFFECT_REQUEST_INVALID");
    assert.equal(missingDiagnostics[0].request_edges, 0);
    assert.equal(missingDiagnostics[0].owner_step_request_edges, 0);
    assert.equal(wrongSourceDiagnostics.length, 1);
    assert.equal(wrongSourceDiagnostics[0].code, "INTENT_GRAPH_EFFECT_REQUEST_INVALID");
    assert.equal(wrongSourceDiagnostics[0].request_edges, 1);
    assert.equal(wrongSourceDiagnostics[0].owner_step_request_edges, 0);
  });

  it("validates graph effect request metadata diagnostics", () => {
    const stepSpan = testSpan(2);
    const effectSpan = testSpan(4);
    const diagnostics = validateTestGraph({
      source: "synthetic.intent",
      nodes: [
        { id: "goal:demo", kind: "Goal", label: "demo", span: testSpan(1) },
        { id: "goal:demo:step:patch", kind: "Step", label: "patch", span: stepSpan },
        {
          id: "goal:demo:step:patch:effect:0",
          kind: "Effect",
          label: "FileWrite",
          span: effectSpan,
          data: {
            family: "file",
            action: "write",
            contractId: "intent.effect.file.write.v0",
            contractArguments: { path: "_0" },
            args: { _0: "./src/app.ts" },
            argKinds: { _0: "string" },
            argSpans: { _0: effectSpan },
            expression: "FileWrite(\"./src/app.ts\")",
          },
        },
      ],
      edges: [
        {
          from: "goal:demo:step:patch",
          to: "goal:demo:step:patch:effect:0",
          kind: "requests",
          data: {
            name: "FileWrite",
            expression: "FileWrite(\"./src/app.ts\")",
            family: "file",
            action: "read",
            contractId: "intent.effect.file.write.v0",
            contractArguments: { path: "_0" },
            args: { _0: "./src/app.ts" },
            argKinds: { _0: "string" },
            argSpans: { _0: effectSpan },
            sourceSpan: stepSpan,
            targetSpan: effectSpan,
          },
        },
      ],
    }).filter((diagnostic) => diagnostic.code === "INTENT_GRAPH_EFFECT_REQUEST_INVALID");

    assert.equal(diagnostics.length, 1);
    assert.equal(diagnostics[0].effect_id, "goal:demo:step:patch:effect:0");
    assert.equal(diagnostics[0].data_is_object, true);
    assert.equal(diagnostics[0].family_matches_target, true);
    assert.equal(diagnostics[0].action_matches_target, false);
    assert.equal(diagnostics[0].args_match_target, true);
    assert.equal(diagnostics[0].arg_spans_match_target, true);
  });

  it("validates graph step plan diagnostics", () => {
    const missingDiagnostics = validateTestGraph({
      source: "synthetic.intent",
      nodes: [
        { id: "goal:demo", kind: "Goal", label: "demo", span: testSpan(1) },
        { id: "goal:demo:step:patch", kind: "Step", label: "patch", span: testSpan(2) },
      ],
      edges: [],
    });
    const wrongSourceDiagnostics = validateTestGraph({
      source: "synthetic.intent",
      nodes: [
        { id: "goal:demo", kind: "Goal", label: "demo", span: testSpan(1) },
        { id: "goal:other", kind: "Goal", label: "other", span: testSpan(2) },
        { id: "goal:demo:step:patch", kind: "Step", label: "patch", span: testSpan(2) },
      ],
      edges: [
        { from: "goal:other", to: "goal:demo:step:patch", kind: "plans" },
      ],
    });

    assert.equal(missingDiagnostics[0].code, "INTENT_GRAPH_STEP_PLAN_INVALID");
    assert.equal(missingDiagnostics[0].plans_edges, 0);
    assert.equal(missingDiagnostics[0].owner_goal_plans_edges, 0);
    assert.equal(wrongSourceDiagnostics[0].code, "INTENT_GRAPH_STEP_PLAN_INVALID");
    assert.equal(wrongSourceDiagnostics[0].plans_edges, 1);
    assert.equal(wrongSourceDiagnostics[0].owner_goal_plans_edges, 0);
  });

  it("validates graph step plan metadata diagnostics", () => {
    const goalSpan = testSpan(1);
    const stepSpan = testSpan(2);
    const diagnostics = validateTestGraph({
      source: "synthetic.intent",
      nodes: [
        { id: "goal:demo", kind: "Goal", label: "demo", span: goalSpan },
        { id: "goal:demo:step:patch", kind: "Step", label: "patch", span: stepSpan },
      ],
      edges: [
        {
          from: "goal:demo",
          to: "goal:demo:step:patch",
          kind: "plans",
          data: {
            goal: "demo",
            step: "wrong",
            index: 0,
            sourceSpan: goalSpan,
            targetSpan: stepSpan,
          },
        },
      ],
    }).filter((diagnostic) => diagnostic.code === "INTENT_GRAPH_STEP_PLAN_INVALID");

    assert.equal(diagnostics.length, 1);
    assert.equal(diagnostics[0].data_is_object, true);
    assert.equal(diagnostics[0].goal_matches_source, true);
    assert.equal(diagnostics[0].step_matches_target, false);
    assert.equal(diagnostics[0].index_matches_target, true);
    assert.equal(diagnostics[0].source_span_matches_goal, true);
    assert.equal(diagnostics[0].target_span_matches_step, true);
  });

  it("validates graph step sequence diagnostics", () => {
    const missingChainDiagnostics = validateTestGraph({
      source: "synthetic.intent",
      nodes: [
        { id: "goal:demo", kind: "Goal", label: "demo", span: testSpan(1) },
        { id: "goal:demo:step:a", kind: "Step", label: "a", span: testSpan(2) },
        { id: "goal:demo:step:b", kind: "Step", label: "b", span: testSpan(3) },
        { id: "goal:demo:verify:0", kind: "Check", label: "ok", span: testSpan(4) },
        { id: "goal:demo:completion", kind: "Completion", label: "demo", span: testSpan(5) },
      ],
      edges: [
        { from: "goal:demo", to: "goal:demo:step:a", kind: "plans" },
        { from: "goal:demo", to: "goal:demo:step:b", kind: "plans" },
        { from: "goal:demo", to: "goal:demo:completion", kind: "completes" },
        { from: "goal:demo:step:b", to: "goal:demo:completion", kind: "produces" },
        { from: "goal:demo:verify:0", to: "goal:demo", kind: "gates" },
        { from: "goal:demo:verify:0", to: "goal:demo:completion", kind: "verifies" },
      ],
    });
    const wrongProducerDiagnostics = validateTestGraph({
      source: "synthetic.intent",
      nodes: [
        { id: "goal:demo", kind: "Goal", label: "demo", span: testSpan(1) },
        { id: "goal:demo:step:a", kind: "Step", label: "a", span: testSpan(2) },
        { id: "goal:demo:step:b", kind: "Step", label: "b", span: testSpan(3) },
        { id: "goal:demo:verify:0", kind: "Check", label: "ok", span: testSpan(4) },
        { id: "goal:demo:completion", kind: "Completion", label: "demo", span: testSpan(5) },
      ],
      edges: [
        { from: "goal:demo", to: "goal:demo:step:a", kind: "plans" },
        { from: "goal:demo", to: "goal:demo:step:b", kind: "plans" },
        { from: "goal:demo:step:a", to: "goal:demo:step:b", kind: "precedes" },
        { from: "goal:demo", to: "goal:demo:completion", kind: "completes" },
        { from: "goal:demo:step:a", to: "goal:demo:completion", kind: "produces" },
        { from: "goal:demo:verify:0", to: "goal:demo", kind: "gates" },
        { from: "goal:demo:verify:0", to: "goal:demo:completion", kind: "verifies" },
      ],
    });
    const invalidMetadataDiagnostics = validateTestGraph({
      source: "synthetic.intent",
      nodes: [
        { id: "goal:demo", kind: "Goal", label: "demo", span: testSpan(1) },
        { id: "goal:demo:step:a", kind: "Step", label: "a", span: testSpan(2) },
        { id: "goal:demo:step:b", kind: "Step", label: "b", span: testSpan(3) },
        { id: "goal:demo:verify:0", kind: "Check", label: "ok", span: testSpan(4) },
        { id: "goal:demo:completion", kind: "Completion", label: "demo", span: testSpan(5) },
      ],
      edges: [
        { from: "goal:demo", to: "goal:demo:step:a", kind: "plans" },
        { from: "goal:demo", to: "goal:demo:step:b", kind: "plans" },
        {
          from: "goal:demo:step:a",
          to: "goal:demo:step:b",
          kind: "precedes",
          data: {
            previousStep: "a",
            nextStep: "wrong",
            previousIndex: 0,
            nextIndex: 1,
            sourceSpan: testSpan(2),
            targetSpan: testSpan(3),
          },
        },
        { from: "goal:demo", to: "goal:demo:completion", kind: "completes" },
        { from: "goal:demo:step:b", to: "goal:demo:completion", kind: "produces" },
        { from: "goal:demo:verify:0", to: "goal:demo", kind: "gates" },
        { from: "goal:demo:verify:0", to: "goal:demo:completion", kind: "verifies" },
      ],
    });

    assert.equal(missingChainDiagnostics.length, 1);
    assert.equal(missingChainDiagnostics[0].code, "INTENT_GRAPH_STEP_SEQUENCE_INVALID");
    assert.equal(missingChainDiagnostics[0].precedes_edges, 0);
    assert.equal(missingChainDiagnostics[0].expected_precedes_edges, 1);
    assert.deepEqual(missingChainDiagnostics[0].head_step_ids, ["goal:demo:step:a", "goal:demo:step:b"]);
    assert.equal(wrongProducerDiagnostics.length, 1);
    assert.equal(wrongProducerDiagnostics[0].code, "INTENT_GRAPH_STEP_SEQUENCE_INVALID");
    assert.deepEqual(wrongProducerDiagnostics[0].completion_producer_step_ids, ["goal:demo:step:a"]);
    assert.equal(wrongProducerDiagnostics[0].expected_completion_producer_step_id, "goal:demo:step:b");
    assert.equal(invalidMetadataDiagnostics.length, 1);
    assert.equal(invalidMetadataDiagnostics[0].code, "INTENT_GRAPH_STEP_SEQUENCE_INVALID");
    assert.equal(invalidMetadataDiagnostics[0].invalid_precedes_metadata.length, 1);
    assert.equal(invalidMetadataDiagnostics[0].invalid_precedes_metadata[0].next_step_matches_target, false);
  });

  it("validates graph goal completion diagnostics", () => {
    const missingCompletionDiagnostics = validateTestGraph({
      source: "synthetic.intent",
      nodes: [
        { id: "goal:demo", kind: "Goal", label: "demo", span: testSpan(1) },
      ],
      edges: [],
    });
    const wrongCompletionDiagnostics = validateTestGraph({
      source: "synthetic.intent",
      nodes: [
        { id: "goal:demo", kind: "Goal", label: "demo", span: testSpan(1) },
        { id: "goal:other:completion", kind: "Completion", label: "other", span: testSpan(2) },
      ],
      edges: [
        { from: "goal:demo", to: "goal:other:completion", kind: "completes" },
      ],
    });

    assert.equal(missingCompletionDiagnostics.length, 1);
    assert.equal(missingCompletionDiagnostics[0].code, "INTENT_GRAPH_GOAL_COMPLETION_INVALID");
    assert.equal(missingCompletionDiagnostics[0].completion_id, "goal:demo:completion");
    assert.equal(missingCompletionDiagnostics[0].completion_node_kind, null);
    assert.equal(wrongCompletionDiagnostics[0].code, "INTENT_GRAPH_COMPLETION_INVALID");
    assert.equal(wrongCompletionDiagnostics[1].code, "INTENT_GRAPH_GOAL_COMPLETION_INVALID");
    assert.deepEqual(wrongCompletionDiagnostics[1].invalid_completes_targets, ["goal:other:completion"]);
  });

  it("validates graph step attachment diagnostics", () => {
    const diagnostics = validateTestGraph({
      source: "synthetic.intent",
      nodes: [
        { id: "goal:demo", kind: "Goal", label: "demo", span: testSpan(1) },
        { id: "goal:demo:step:patch", kind: "Step", label: "patch", span: testSpan(2), data: { effects: ["FileWrite"] } },
        { id: "goal:demo:capability:0", kind: "Capability", label: "file", span: testSpan(3) },
        { id: "goal:demo:step:patch:requirement:0", kind: "Check", label: "input.ready", span: testSpan(4), data: { scope: "step" } },
        { id: "goal:demo:step:patch:approval:0", kind: "Approval", label: "maintainer", span: testSpan(5) },
        { id: "goal:demo:step:patch:checkpoint:0", kind: "Checkpoint", label: "before", span: testSpan(6) },
        { id: "goal:demo:step:patch:timeout:0", kind: "Policy", label: "5m", span: testSpan(7), data: { policyKind: "timeout" } },
        { id: "goal:demo:step:patch:retry:0", kind: "Policy", label: "max 2", span: testSpan(8), data: { policyKind: "retry" } },
        { id: "goal:demo:step:patch:effect:0", kind: "Effect", label: "FileWrite", span: testSpan(9), data: { approvalRequired: true } },
        { id: "goal:demo:verify:0", kind: "Check", label: "ok", span: testSpan(10) },
        { id: "goal:demo:completion", kind: "Completion", label: "demo", span: testSpan(11) },
      ],
      edges: [
        { from: "goal:demo:capability:0", to: "goal:demo", kind: "authorizes" },
        { from: "goal:demo", to: "goal:demo:step:patch", kind: "plans" },
        { from: "goal:demo:step:patch", to: "goal:demo:step:patch:effect:0", kind: "requests" },
        { from: "goal:demo:capability:0", to: "goal:demo:step:patch:effect:0", kind: "authorizes" },
        { from: "goal:demo", to: "goal:demo:completion", kind: "completes" },
        { from: "goal:demo:step:patch", to: "goal:demo:completion", kind: "produces" },
        { from: "goal:demo:step:patch:requirement:0", to: "goal:demo", kind: "gates" },
        { from: "goal:demo:verify:0", to: "goal:demo", kind: "gates" },
        { from: "goal:demo:verify:0", to: "goal:demo:completion", kind: "verifies" },
      ],
    });

    assert.deepEqual(diagnostics.map((diagnostic) => diagnostic.code), [
      "INTENT_GRAPH_STEP_ATTACHMENT_INVALID",
      "INTENT_GRAPH_STEP_ATTACHMENT_INVALID",
      "INTENT_GRAPH_STEP_ATTACHMENT_INVALID",
      "INTENT_GRAPH_STEP_ATTACHMENT_INVALID",
      "INTENT_GRAPH_STEP_ATTACHMENT_INVALID",
    ]);
    assert.equal(diagnostics[0].node_id, "goal:demo:step:patch:requirement:0");
    assert.deepEqual(diagnostics[0].missing_edges, [
      { kind: "requires", from: "goal:demo:step:patch:requirement:0", to: "goal:demo:step:patch" },
    ]);
    assert.equal(diagnostics[1].node_id, "goal:demo:step:patch:approval:0");
    assert.deepEqual(diagnostics[1].missing_approval_targets, ["goal:demo:step:patch:effect:0"]);
    assert.equal(diagnostics[2].node_id, "goal:demo:step:patch:checkpoint:0");
    assert.equal(diagnostics[3].missing_edges[0].kind, "timeouts");
    assert.equal(diagnostics[4].missing_edges[0].kind, "retries");
  });

  it("validates graph completion edge diagnostics", () => {
    const missingProducesDiagnostics = validateTestGraph({
      source: "synthetic.intent",
      nodes: [
        { id: "goal:demo", kind: "Goal", label: "demo", span: testSpan(1) },
        { id: "goal:demo:verify:0", kind: "Check", label: "ok", span: testSpan(2) },
        { id: "goal:demo:completion", kind: "Completion", label: "demo", span: testSpan(3) },
      ],
      edges: [
        { from: "goal:demo", to: "goal:demo:completion", kind: "completes" },
        { from: "goal:demo:verify:0", to: "goal:demo:completion", kind: "verifies" },
      ],
    });
    const duplicateProducesDiagnostics = validateTestGraph({
      source: "synthetic.intent",
      nodes: [
        { id: "goal:demo", kind: "Goal", label: "demo", span: testSpan(1) },
        { id: "goal:demo:step:a", kind: "Step", label: "a", span: testSpan(2) },
        { id: "goal:demo:step:b", kind: "Step", label: "b", span: testSpan(3) },
        { id: "goal:demo:verify:0", kind: "Check", label: "ok", span: testSpan(4) },
        { id: "goal:demo:completion", kind: "Completion", label: "demo", span: testSpan(5) },
      ],
      edges: [
        { from: "goal:demo", to: "goal:demo:completion", kind: "completes" },
        { from: "goal:demo:step:a", to: "goal:demo:completion", kind: "produces" },
        { from: "goal:demo:step:b", to: "goal:demo:completion", kind: "produces" },
        { from: "goal:demo:verify:0", to: "goal:demo:completion", kind: "verifies" },
      ],
    });
    const missingVerifyAndGuardDiagnostics = validateTestGraph({
      source: "synthetic.intent",
      nodes: [
        { id: "goal:demo", kind: "Goal", label: "demo", span: testSpan(1) },
        { id: "goal:demo:step:a", kind: "Step", label: "a", span: testSpan(2) },
        { id: "goal:demo:invariant:0", kind: "Invariant", label: "rule", span: testSpan(3) },
        { id: "goal:demo:completion", kind: "Completion", label: "demo", span: testSpan(4) },
      ],
      edges: [
        { from: "goal:demo", to: "goal:demo:completion", kind: "completes" },
        { from: "goal:demo:step:a", to: "goal:demo:completion", kind: "produces" },
      ],
    });
    const missingCitationDiagnostics = validateTestGraph({
      source: "synthetic.intent",
      nodes: [
        { id: "goal:demo", kind: "Goal", label: "demo", span: testSpan(1) },
        { id: "goal:demo:step:a", kind: "Step", label: "a", span: testSpan(2) },
        { id: "goal:demo:verify:0", kind: "Check", label: "ok", span: testSpan(3) },
        {
          id: "goal:demo:completion",
          kind: "Completion",
          label: "demo",
          span: testSpan(4),
          data: {
            provenance: {
              required: true,
              requirements: [{ requirement: "all_outputs_cited", span: testSpan(3) }],
              invariants: [],
              citations: [{ memory: "session", key: null, target: "session", step: "a", span: testSpan(2) }],
            },
          },
        },
      ],
      edges: [
        { from: "goal:demo", to: "goal:demo:completion", kind: "completes" },
        { from: "goal:demo:step:a", to: "goal:demo:completion", kind: "produces" },
        { from: "goal:demo:verify:0", to: "goal:demo:completion", kind: "verifies" },
      ],
    });
    const missingCheckpointDiagnostics = validateTestGraph({
      source: "synthetic.intent",
      nodes: [
        { id: "goal:demo", kind: "Goal", label: "demo", span: testSpan(1) },
        { id: "goal:demo:step:a", kind: "Step", label: "a", span: testSpan(2) },
        { id: "goal:demo:verify:0", kind: "Check", label: "ok", span: testSpan(3) },
        {
          id: "goal:demo:completion",
          kind: "Completion",
          label: "demo",
          span: testSpan(4),
          data: {
            checkpoint: {
              required: true,
              requirements: [{ requirement: "final_state_checkpointed", span: testSpan(3) }],
              invariants: [],
              checkpoints: [{ checkpoint: "final state", step: "a", span: testSpan(2) }],
            },
          },
        },
      ],
      edges: [
        { from: "goal:demo", to: "goal:demo:completion", kind: "completes" },
        { from: "goal:demo:step:a", to: "goal:demo:completion", kind: "produces" },
        { from: "goal:demo:verify:0", to: "goal:demo:completion", kind: "verifies" },
      ],
    });

    assert.equal(missingProducesDiagnostics[0].code, "INTENT_GRAPH_COMPLETION_INVALID");
    assert.equal(missingProducesDiagnostics[0].completes_edges, 1);
    assert.equal(missingProducesDiagnostics[0].produces_edges, 0);
    assert.equal(missingProducesDiagnostics[0].verifies_edges, 1);
    assert.equal(duplicateProducesDiagnostics[0].code, "INTENT_GRAPH_COMPLETION_INVALID");
    assert.equal(duplicateProducesDiagnostics[0].completes_edges, 1);
    assert.equal(duplicateProducesDiagnostics[0].produces_edges, 2);
    assert.equal(duplicateProducesDiagnostics[0].verifies_edges, 1);
    assert.equal(missingVerifyAndGuardDiagnostics[0].code, "INTENT_GRAPH_COMPLETION_INVALID");
    assert.equal(missingVerifyAndGuardDiagnostics[0].verifies_edges, 0);
    assert.equal(missingVerifyAndGuardDiagnostics[0].guards_edges, 0);
    assert.equal(missingVerifyAndGuardDiagnostics[0].expected_guard_edges, 1);
    assert.equal(missingCitationDiagnostics[0].code, "INTENT_GRAPH_COMPLETION_INVALID");
    assert.equal(missingCitationDiagnostics[0].provenance_required, true);
    assert.equal(missingCitationDiagnostics[0].citation_edges, 0);
    assert.equal(missingCitationDiagnostics[0].has_required_citation_edges, false);
    assert.equal(missingCheckpointDiagnostics[0].code, "INTENT_GRAPH_COMPLETION_INVALID");
    assert.equal(missingCheckpointDiagnostics[0].checkpoint_required, true);
    assert.equal(missingCheckpointDiagnostics[0].checkpoint_edges, 0);
    assert.equal(missingCheckpointDiagnostics[0].has_required_checkpoint_edges, false);
  });

  it("validates graph completion payload diagnostics", () => {
    const diagnostics = validateTestGraph({
      source: "synthetic.intent",
      nodes: [
        { id: "goal:demo:completion", kind: "Completion", label: "demo", span: testSpan(1), data: { outputType: "", outputTypeSpan: null } },
        { id: "goal:other:completion", kind: "Completion", label: "other", span: testSpan(2), data: { outputType: "Report", outputTypeSpan: { file: "synthetic.intent", start: { line: 0, column: 1 }, end: { line: 1, column: 1 } } } },
        { id: "goal:missing-span:completion", kind: "Completion", label: "missing span", span: testSpan(3), data: { outputType: "Report", outputTypeSpan: null } },
        { id: "goal:unexpected-span:completion", kind: "Completion", label: "unexpected span", span: testSpan(4), data: { outputType: null, outputTypeSpan: testSpan(4) } },
        { id: "goal:missing-provenance:completion", kind: "Completion", label: "missing provenance", span: testSpan(5), data: { provenance: null } },
        {
          id: "goal:missing-citation:completion",
          kind: "Completion",
          label: "missing citation",
          span: testSpan(6),
          data: { provenance: { required: true, requirements: [], invariants: [], citations: [] } },
        },
        { id: "goal:missing-checkpoint:completion", kind: "Completion", label: "missing checkpoint", span: testSpan(7), data: { checkpoint: null } },
        {
          id: "goal:missing-checkpoint-record:completion",
          kind: "Completion",
          label: "missing checkpoint record",
          span: testSpan(8),
          data: { checkpoint: { required: true, requirements: [], invariants: [], checkpoints: [] } },
        },
      ],
      edges: [],
    }).filter((diagnostic) => diagnostic.code === "INTENT_GRAPH_COMPLETION_INVALID" && "output_type_is_valid" in diagnostic);

    assert.equal(diagnostics.length, 8);
    assert.equal(diagnostics[0].code, "INTENT_GRAPH_COMPLETION_INVALID");
    assert.equal(diagnostics[0].completion_id, "goal:demo:completion");
    assert.equal(diagnostics[0].output_type_is_valid, false);
    assert.equal(diagnostics[0].output_type_span_is_valid, false);
    assert.equal(diagnostics[1].code, "INTENT_GRAPH_COMPLETION_INVALID");
    assert.equal(diagnostics[1].completion_id, "goal:other:completion");
    assert.equal(diagnostics[1].output_type_is_valid, true);
    assert.equal(diagnostics[1].output_type_span_is_valid, false);
    assert.equal(diagnostics[2].completion_id, "goal:missing-span:completion");
    assert.equal(diagnostics[2].output_type_is_valid, true);
    assert.equal(diagnostics[2].output_type_span_is_valid, false);
    assert.equal(diagnostics[3].completion_id, "goal:unexpected-span:completion");
    assert.equal(diagnostics[3].output_type_is_valid, true);
    assert.equal(diagnostics[3].output_type_span_is_valid, false);
    assert.equal(diagnostics[4].completion_id, "goal:missing-provenance:completion");
    assert.equal(diagnostics[4].provenance_is_valid, false);
    assert.equal(diagnostics[5].completion_id, "goal:missing-citation:completion");
    assert.equal(diagnostics[5].provenance_is_valid, true);
    assert.equal(diagnostics[5].provenance_has_required_citations, false);
    assert.equal(diagnostics[6].completion_id, "goal:missing-checkpoint:completion");
    assert.equal(diagnostics[6].checkpoint_is_valid, false);
    assert.equal(diagnostics[7].completion_id, "goal:missing-checkpoint-record:completion");
    assert.equal(diagnostics[7].checkpoint_is_valid, true);
    assert.equal(diagnostics[7].checkpoint_has_required_records, false);
  });

  it("validates graph completion metadata parity diagnostics", () => {
    const goalSpan = testSpan(1);
    const stepOutputSpan = testSpanOffset(2, 20);
    const memorySpan = testSpan(3);
    const citationSpan = testSpanOffset(4, 40);
    const checkpointSpan = testSpan(5);
    const checkSpan = testSpan(6);
    const completionSpan = testSpan(7);
    const diagnostics = validateTestGraph({
      source: "synthetic.intent",
      nodes: [
        { id: "goal:demo", kind: "Goal", label: "demo", span: goalSpan, data: { title: "Demo", parameters: [], outputType: "Report", outputTypeSpan: completionSpan } },
        {
          id: "goal:demo:memory:0",
          kind: "Memory",
          label: "session",
          span: memorySpan,
          data: {
            retention: ["session until completion"],
            retentionRules: [{ raw: "session until completion", subject: { raw: "session" }, until: { raw: "completion" } }],
            keys: [],
          },
        },
        {
          id: "goal:demo:step:final",
          kind: "Step",
          label: "final",
          span: stepOutputSpan,
          data: {
            inputs: [],
            outputType: "Report",
            outputTypeSpan: stepOutputSpan,
            effects: [],
            requirements: [],
            checkpoints: ["final state"],
            approvals: [],
            timeouts: [],
            retries: [],
            memoryAccesses: ["session.evidence"],
          },
        },
        { id: "goal:demo:step:final:checkpoint:0", kind: "Checkpoint", label: "final state", span: checkpointSpan, data: { checkpoint: "final state", ownerStep: "final" } },
        { id: "goal:demo:verify:0", kind: "Check", label: "done", span: checkSpan, data: { requirement: "done", scope: "goal" } },
        {
          id: "goal:demo:completion",
          kind: "Completion",
          label: "demo",
          span: completionSpan,
          data: {
            outputType: "Report",
            outputTypeSpan: completionSpan,
            provenance: {
              required: true,
              requirements: [{ requirement: "memory_provenance_complete", span: checkSpan }],
              invariants: [],
              citations: [{ memory: "session", key: null, target: "session.wrong", step: "final", span: citationSpan }],
            },
            checkpoint: {
              required: true,
              requirements: [{ requirement: "final_state_checkpointed", span: checkSpan }],
              invariants: [],
              checkpoints: [{ checkpoint: "wrong final state", step: "final", span: checkpointSpan }],
            },
          },
        },
      ],
      edges: [
        { from: "goal:demo", to: "goal:demo:memory:0", kind: "declares" },
        { from: "goal:demo", to: "goal:demo:step:final", kind: "plans" },
        { from: "goal:demo", to: "goal:demo:completion", kind: "completes" },
        { from: "goal:demo:step:final", to: "goal:demo:completion", kind: "produces", data: { type: "Report", sourceSpan: stepOutputSpan, targetSpan: completionSpan } },
        { from: "goal:demo:step:final", to: "goal:demo:memory:0", kind: "writes", data: { access: "write", memory: "session", key: null, target: "session.evidence", sourceSpan: stepOutputSpan, targetSpan: memorySpan } },
        { from: "goal:demo:memory:0", to: "goal:demo:step:final", kind: "cites", data: { access: "cite", memory: "session", key: null, target: "session.evidence", sourceSpan: memorySpan, targetSpan: citationSpan } },
        { from: "goal:demo:step:final", to: "goal:demo:step:final:checkpoint:0", kind: "checkpoints", data: { checkpoint: "final state" } },
        { from: "goal:demo:verify:0", to: "goal:demo", kind: "gates", data: { requirement: "done", scope: "goal", sourceSpan: checkSpan, targetSpan: goalSpan } },
        { from: "goal:demo:verify:0", to: "goal:demo:completion", kind: "verifies", data: { requirement: "done", scope: "goal", sourceSpan: checkSpan, targetSpan: completionSpan } },
      ],
    }).filter((diagnostic) => diagnostic.code === "INTENT_GRAPH_COMPLETION_METADATA_INVALID");

    assert.equal(diagnostics.length, 2);
    assert.equal(diagnostics[0].field, "provenance.citations");
    assert.equal(diagnostics[0].declared_values[0].target, "session.wrong");
    assert.equal(diagnostics[0].edge_values[0].target, "session.evidence");
    assert.deepEqual(diagnostics[0].mismatched_indexes, [0]);
    assert.equal(diagnostics[1].field, "checkpoint.checkpoints");
    assert.equal(diagnostics[1].declared_values[0].checkpoint, "wrong final state");
    assert.equal(diagnostics[1].edge_values[0].checkpoint, "final state");
    assert.deepEqual(diagnostics[1].mismatched_indexes, [0]);
  });

  it("validates graph completion citation backing diagnostics", () => {
    const memorySpan = testSpan(3);
    const citationSpan = testSpan(4);
    const diagnostics = validateTestGraph({
      source: "synthetic.intent",
      nodes: [
        { id: "goal:demo", kind: "Goal", label: "demo", span: testSpan(1) },
        { id: "goal:demo:step:final", kind: "Step", label: "final", span: testSpan(2), data: { memoryAccesses: ["session.evidence"] } },
        { id: "goal:demo:memory:0", kind: "Memory", label: "session", span: memorySpan },
        { id: "goal:demo:verify:0", kind: "Check", label: "done", span: testSpan(5), data: { requirement: "done", scope: "goal" } },
        {
          id: "goal:demo:completion",
          kind: "Completion",
          label: "demo",
          span: testSpan(6),
          data: {
            provenance: {
              required: true,
              requirements: [{ requirement: "memory_provenance_complete", span: testSpan(5) }],
              invariants: [],
              citations: [{ memory: "session", key: null, target: "session.evidence", step: "final", span: citationSpan }],
            },
          },
        },
      ],
      edges: [
        { from: "goal:demo", to: "goal:demo:memory:0", kind: "declares" },
        { from: "goal:demo", to: "goal:demo:step:final", kind: "plans" },
        { from: "goal:demo", to: "goal:demo:completion", kind: "completes" },
        { from: "goal:demo:step:final", to: "goal:demo:completion", kind: "produces" },
        { from: "goal:demo:memory:0", to: "goal:demo:step:final", kind: "cites", data: { access: "cite", memory: "session", key: null, target: "session.evidence", sourceSpan: memorySpan, targetSpan: citationSpan } },
        { from: "goal:demo:verify:0", to: "goal:demo", kind: "gates" },
        { from: "goal:demo:verify:0", to: "goal:demo:completion", kind: "verifies" },
      ],
    }).filter((diagnostic) => diagnostic.code === "INTENT_GRAPH_COMPLETION_METADATA_INVALID");

    assert.equal(diagnostics.length, 1);
    assert.equal(diagnostics[0].field, "provenance.citation_backing");
    assert.equal(diagnostics[0].unbacked_citations[0].target, "session.evidence");
    assert.equal(diagnostics[0].write_edges.length, 0);
  });

  it("validates graph typed edge contract diagnostics", () => {
    const diagnostics = validateTestGraph({
      source: "synthetic.intent",
      nodes: [
        { id: "goal:demo", kind: "Goal", label: "demo", span: testSpan(1), data: { outputType: "Report" } },
        { id: "goal:other", kind: "Goal", label: "other", span: testSpan(6), data: { outputType: "Other" } },
        { id: "goal:other:completion", kind: "Completion", label: "other", span: testSpan(7), data: { outputType: "Other" } },
        { id: "goal:demo:input:ticket", kind: "Input", label: "ticket", span: testSpan(2), data: { scope: "goal", type: "Ticket" } },
        { id: "goal:demo:step:patch", kind: "Step", label: "patch", span: testSpan(3), data: { outputType: "Patch" } },
        { id: "goal:demo:step:fallback", kind: "Step", label: "fallback", span: testSpan(8), data: { outputType: "Fallback", outputTypeSpan: null } },
        { id: "goal:demo:step:patch:input:ticket", kind: "Input", label: "ticket", span: testSpan(4), data: { scope: "step", type: "Ticket" } },
        { id: "goal:demo:step:patch:requirement:0", kind: "Check", label: "ready", span: testSpan(5), data: { scope: "step", ownerStep: "patch", assertion: "Require", requirement: "ticket.ready" } },
        { id: "goal:demo:verify:0", kind: "Check", label: "ok", span: testSpan(3) },
        { id: "goal:demo:completion", kind: "Completion", label: "demo", span: testSpan(4), data: { outputType: "Report", outputTypeSpan: testSpan(4) } },
      ],
      edges: [
        { from: "goal:demo", to: "goal:demo:completion", kind: "completes" },
        { from: "goal:demo:input:ticket", to: "goal:other", kind: "supplies", data: { parameter: "issue", type: "Issue", sourceSpan: testSpan(1), targetSpan: testSpan(1) } },
        { from: "goal:demo:input:ticket", to: "goal:demo:step:patch:input:ticket", kind: "data", data: { parameter: "ticket_id", type: "Issue", sourceSpan: testSpan(1), targetSpan: testSpan(5) } },
        { from: "goal:demo:step:patch:input:ticket", to: "goal:demo:step:patch", kind: "requires", data: { parameter: "ticket_id", type: "Issue", targetSpan: testSpan(5) } },
        { from: "goal:demo:step:patch:requirement:0", to: "goal:demo:step:patch", kind: "requires", data: { requirement: "ticket.closed" } },
        { from: "goal:demo:step:patch", to: "goal:demo:completion", kind: "produces", data: { type: "Report", sourceSpan: testSpan(2), targetSpan: testSpan(4) } },
        { from: "goal:demo:step:fallback", to: "goal:demo:completion", kind: "produces", data: { type: "Fallback", sourceSpan: testSpan(8), targetSpan: testSpan(4) } },
        { from: "goal:demo:verify:0", to: "goal:other", kind: "gates", data: { requirement: "closed", scope: "step", sourceSpan: testSpan(1), targetSpan: testSpan(6) } },
        { from: "goal:demo:verify:0", to: "goal:other:completion", kind: "verifies", data: { requirement: "closed", scope: "step", sourceSpan: testSpan(1), targetSpan: testSpan(6) } },
        { from: "goal:demo:verify:0", to: "goal:demo:completion", kind: "verifies" },
      ],
    }).filter((diagnostic) => diagnostic.code === "INTENT_GRAPH_TYPED_EDGE_INVALID");

    assert.equal(diagnostics.length, 8);
    assert.equal(diagnostics[0].edge, "supplies");
    assert.deepEqual(diagnostics[0].checks.map((check) => [check.name, check.ok]), [
      ["owner_goal_matches_target", false],
      ["parameter_matches_source", false],
      ["type_matches_source", false],
      ["source_span_matches_source", false],
      ["target_span_matches_source", false],
    ]);
    assert.equal(diagnostics[1].edge, "data");
    assert.equal(diagnostics[1].from, "goal:demo:input:ticket");
    assert.equal(diagnostics[1].to, "goal:demo:step:patch:input:ticket");
    assert.deepEqual(diagnostics[1].checks.map((check) => [check.name, check.ok]), [
      ["parameter_matches_target", false],
      ["type_matches_source", false],
      ["type_matches_target", false],
      ["source_span_matches_source", false],
      ["target_span_matches_target", false],
    ]);
    assert.equal(diagnostics[2].edge, "requires");
    assert.deepEqual(diagnostics[2].checks.map((check) => [check.name, check.ok]), [
      ["owner_step_matches_target", true],
      ["parameter_matches_source", false],
      ["type_matches_source", false],
      ["target_span_matches_source", false],
    ]);
    assert.equal(diagnostics[3].edge, "requires");
    assert.deepEqual(diagnostics[3].checks.map((check) => [check.name, check.ok]), [
      ["owner_step_matches_target", true],
      ["requirement_matches_source", false],
    ]);
    assert.equal(diagnostics[4].edge, "produces");
    assert.deepEqual(diagnostics[4].checks.map((check) => [check.name, check.ok]), [
      ["type_matches_source", false],
      ["type_matches_target", true],
      ["source_span_matches_source", false],
      ["target_span_matches_target", true],
    ]);
    assert.equal(diagnostics[5].edge, "produces");
    assert.deepEqual(diagnostics[5].checks.map((check) => [check.name, check.ok]), [
      ["type_matches_source", true],
      ["type_matches_target", false],
      ["source_span_matches_source", false],
      ["target_span_matches_target", true],
    ]);
    assert.equal(diagnostics[6].edge, "gates");
    assert.deepEqual(diagnostics[6].checks.map((check) => [check.name, check.ok]), [
      ["owner_goal_matches_target", false],
      ["requirement_matches_source", false],
      ["scope_matches_source", false],
      ["source_span_matches_source", false],
      ["target_span_matches_target", true],
    ]);
    assert.equal(diagnostics[7].edge, "verifies");
    assert.deepEqual(diagnostics[7].checks.map((check) => [check.name, check.ok]), [
      ["owner_completion_matches_target", false],
      ["requirement_matches_source", false],
      ["scope_matches_source", false],
      ["source_span_matches_source", false],
      ["target_span_matches_target", false],
    ]);
  });

  it("validates graph typed edge span offsets", () => {
    const sourceSpan = testSpanOffset(2, 20);
    const targetSpan = testSpanOffset(3, 40);
    const wrongSourceOffset = testSpanOffset(2, 21);
    const validDiagnostics = validateTestGraph({
      source: "synthetic.intent",
      nodes: [
        { id: "goal:demo:input:ticket", kind: "Input", label: "ticket", span: sourceSpan, data: { scope: "goal", type: "Ticket" } },
        { id: "goal:demo:step:patch:input:ticket", kind: "Input", label: "ticket", span: targetSpan, data: { scope: "step", type: "Ticket" } },
      ],
      edges: [
        { from: "goal:demo:input:ticket", to: "goal:demo:step:patch:input:ticket", kind: "data", data: { parameter: "ticket", type: "Ticket", sourceSpan, targetSpan } },
      ],
    }).filter((diagnostic) => diagnostic.code === "INTENT_GRAPH_TYPED_EDGE_INVALID");
    const invalidDiagnostics = validateTestGraph({
      source: "synthetic.intent",
      nodes: [
        { id: "goal:demo:input:ticket", kind: "Input", label: "ticket", span: sourceSpan, data: { scope: "goal", type: "Ticket" } },
        { id: "goal:demo:step:patch:input:ticket", kind: "Input", label: "ticket", span: targetSpan, data: { scope: "step", type: "Ticket" } },
      ],
      edges: [
        { from: "goal:demo:input:ticket", to: "goal:demo:step:patch:input:ticket", kind: "data", data: { parameter: "ticket", type: "Ticket", sourceSpan: wrongSourceOffset, targetSpan } },
      ],
    }).filter((diagnostic) => diagnostic.code === "INTENT_GRAPH_TYPED_EDGE_INVALID");

    assert.deepEqual(validDiagnostics, []);
    assert.equal(invalidDiagnostics.length, 1);
    assert.deepEqual(invalidDiagnostics[0].checks.map((check) => [check.name, check.ok]), [
      ["parameter_matches_target", true],
      ["type_matches_source", true],
      ["type_matches_target", true],
      ["source_span_matches_source", false],
      ["target_span_matches_target", true],
    ]);
    assert.equal(invalidDiagnostics[0].checks[3].actual.start.offset, 21);
    assert.equal(invalidDiagnostics[0].checks[3].expected.start.offset, 20);
  });

  it("validates graph invariant payload diagnostics", () => {
    const diagnostics = validateTestGraph({
      source: "synthetic.intent",
      nodes: [
        { id: "goal:demo:invariant:0", kind: "Invariant", label: "bad assertion", span: testSpan(1), data: { assertion: "Block", invariant: "secret_write" } },
        { id: "goal:demo:invariant:1", kind: "Invariant", label: "blank invariant", span: testSpan(2), data: { invariant: "" } },
      ],
      edges: [],
    }).filter((diagnostic) => diagnostic.code === "INTENT_GRAPH_INVARIANT_INVALID");

    assert.equal(diagnostics.length, 2);
    assert.equal(diagnostics[0].code, "INTENT_GRAPH_INVARIANT_INVALID");
    assert.equal(diagnostics[0].invariant_id, "goal:demo:invariant:0");
    assert.equal(diagnostics[0].assertion, "Block");
    assert.equal(diagnostics[0].assertion_is_valid, false);
    assert.equal(diagnostics[0].invariant_is_nonempty, true);
    assert.equal(diagnostics[1].code, "INTENT_GRAPH_INVARIANT_INVALID");
    assert.equal(diagnostics[1].invariant_id, "goal:demo:invariant:1");
    assert.equal(diagnostics[1].assertion_is_valid, true);
    assert.equal(diagnostics[1].invariant_is_nonempty, false);
  });

  it("validates graph invariant constraint diagnostics", () => {
    const diagnostics = validateTestGraph({
      source: "synthetic.intent",
      nodes: [
        { id: "goal:demo", kind: "Goal", label: "demo", span: testSpan(1) },
        { id: "goal:other", kind: "Goal", label: "other", span: testSpan(2) },
        { id: "goal:demo:invariant:0", kind: "Invariant", label: "missing", span: testSpan(3) },
        { id: "goal:demo:invariant:1", kind: "Invariant", label: "wrong", span: testSpan(4) },
        { id: "goal:demo:invariant:2", kind: "Invariant", label: "duplicate", span: testSpan(5) },
      ],
      edges: [
        { from: "goal:demo:invariant:1", to: "goal:other", kind: "constrains" },
        { from: "goal:demo:invariant:2", to: "goal:demo", kind: "constrains" },
        { from: "goal:demo:invariant:2", to: "goal:other", kind: "constrains" },
      ],
    }).filter((diagnostic) => diagnostic.code === "INTENT_GRAPH_INVARIANT_CONSTRAINT_INVALID");

    assert.equal(diagnostics.length, 3);
    assert.equal(diagnostics[0].invariant_id, "goal:demo:invariant:0");
    assert.equal(diagnostics[0].constrains_edges, 0);
    assert.equal(diagnostics[0].owner_goal_constrains_edges, 0);
    assert.equal(diagnostics[1].invariant_id, "goal:demo:invariant:1");
    assert.equal(diagnostics[1].constrains_edges, 1);
    assert.equal(diagnostics[1].owner_goal_constrains_edges, 0);
    assert.equal(diagnostics[2].invariant_id, "goal:demo:invariant:2");
    assert.equal(diagnostics[2].constrains_edges, 2);
    assert.equal(diagnostics[2].owner_goal_constrains_edges, 1);
  });

  it("validates graph invariant guard diagnostics", () => {
    const diagnostics = validateTestGraph({
      source: "synthetic.intent",
      nodes: [
        { id: "goal:demo", kind: "Goal", label: "demo", span: testSpan(1) },
        { id: "goal:demo:step:patch", kind: "Step", label: "patch", span: testSpan(2), data: { effects: ["FileWrite"], requirements: ["synthetic"], checkpoints: ["before patch"], timeouts: ["5m"], retries: ["5m"] } },
        { id: "goal:demo:verify:0", kind: "Check", label: "ok", span: testSpan(3) },
        { id: "goal:demo:capability:0", kind: "Capability", label: "file", span: testSpan(3) },
        { id: "goal:demo:completion", kind: "Completion", label: "demo", span: testSpan(4) },
        { id: "goal:demo:invariant:0", kind: "Invariant", label: "deny secret write", span: testSpan(5) },
        { id: "goal:demo:step:patch:effect:0", kind: "Effect", label: "FileWrite", span: testSpan(6) },
        { id: "goal:demo:step:patch:checkpoint:0", kind: "Checkpoint", label: "before", span: testSpan(7) },
        { id: "goal:demo:step:patch:requirement:0", kind: "Check", label: "input.ready", span: testSpan(8), data: { scope: "step" } },
        { id: "goal:demo:step:patch:timeout:0", kind: "Policy", label: "5m", span: testSpan(9), data: { policyKind: "timeout" } },
        { id: "goal:demo:step:patch:retry:0", kind: "Policy", label: "max 2", span: testSpan(10), data: { policyKind: "retry" } },
      ],
      edges: [
        { from: "goal:demo:capability:0", to: "goal:demo", kind: "authorizes" },
        { from: "goal:demo", to: "goal:demo:step:patch", kind: "plans" },
        { from: "goal:demo", to: "goal:demo:completion", kind: "completes" },
        { from: "goal:demo:step:patch", to: "goal:demo:completion", kind: "produces" },
        { from: "goal:demo:verify:0", to: "goal:demo", kind: "gates" },
        { from: "goal:demo:verify:0", to: "goal:demo:completion", kind: "verifies" },
        { from: "goal:demo:step:patch", to: "goal:demo:step:patch:effect:0", kind: "requests" },
        { from: "goal:demo:capability:0", to: "goal:demo:step:patch:effect:0", kind: "authorizes" },
        { from: "goal:demo:step:patch", to: "goal:demo:step:patch:checkpoint:0", kind: "checkpoints", data: { checkpoint: "before patch" } },
        { from: "goal:demo:step:patch:requirement:0", to: "goal:demo:step:patch", kind: "requires", data: { requirement: "synthetic" } },
        { from: "goal:demo:step:patch:requirement:0", to: "goal:demo", kind: "gates" },
        { from: "goal:demo:step:patch:timeout:0", to: "goal:demo:step:patch", kind: "timeouts", data: { policy: "5m" } },
        { from: "goal:demo:step:patch:retry:0", to: "goal:demo:step:patch", kind: "retries", data: { policy: "5m" } },
        { from: "goal:demo:invariant:0", to: "goal:demo", kind: "constrains" },
        { from: "goal:demo:invariant:0", to: "goal:demo:completion", kind: "guards" },
      ],
    }).filter((diagnostic) => diagnostic.code === "INTENT_GRAPH_GUARD_INVALID");

    assert.equal(diagnostics.length, 1);
    assert.equal(diagnostics[0].code, "INTENT_GRAPH_GUARD_INVALID");
    assert.equal(diagnostics[0].invariant_id, "goal:demo:invariant:0");
    assert.deepEqual(diagnostics[0].missing_guard_targets, [
      "goal:demo:step:patch:effect:0",
      "goal:demo:step:patch:checkpoint:0",
      "goal:demo:step:patch:requirement:0",
      "goal:demo:step:patch:timeout:0",
      "goal:demo:step:patch:retry:0",
    ]);
  });

  it("validates CLI outputs against versioned schemas", () => {
    const astSchema = readJson(AST_SCHEMA);
    const checkSchema = readJson(CHECK_SCHEMA);
    const graphSchema = readJson(GRAPH_SCHEMA);
    const effectContractSchema = readJson(EFFECT_CONTRACT_SCHEMA);
    const effectContracts = runJson(["contracts"]);
    const ast = runJson(["parse", VALID_DEPENDENCY_GRAPH]);
    const importAst = runJson(["parse", VALID_IMPORTS]);
    const validCheck = runJson(["check", VALID_DEPENDENCY_GRAPH]);
    const invalidCheck = JSON.parse(run(["check", INVALID_UNRESOLVED_TYPE]).stdout);
    const graph = runJson(["graph", VALID_DEPENDENCY_GRAPH]);
    const deployGraph = runJson(["graph", VALID_DEPLOY_TARGET]);
    const commitGraph = runJson(["graph", VALID_GIT_COMMIT_MESSAGE]);
    const approvalGraph = runJson(["graph", VALID_STEP_APPROVAL_GRAPH]);
    const policyGraph = runJson(["graph", VALID_STEP_POLICY_GRAPH]);
    const contextGraph = runJson(["graph", VALID_CONTEXT_TRUST_GRAPH]);
    const memoryGraph = runJson(["graph", VALID_MEMORY_FLOW_GRAPH]);
    const secretGraph = runJson(["graph", VALID_SECRET_READ]);
    const ticketGraph = runJson(["graph", VALID_TICKET_UPDATE]);
    const examplePayloads = EXECUTABLE_EXAMPLES.map((example) => {
      return {
        ast: runJson(["parse", example]),
        check: runJson(["check", example]),
        graph: runJson(["graph", example]),
      };
    });

    assert.deepEqual(validateSchema(astSchema, ast), []);
    assert.deepEqual(validateSchema(astSchema, importAst), []);
    assert.deepEqual(validateSchema(checkSchema, validCheck), []);
    assert.deepEqual(validateSchema(checkSchema, invalidCheck), []);
    assert.deepEqual(validateSchema(effectContractSchema, effectContracts), []);
    assert.deepEqual(validateSchema(graphSchema, graph), []);
    assert.deepEqual(validateSchema(graphSchema, deployGraph), []);
    assert.deepEqual(validateSchema(graphSchema, commitGraph), []);
    assert.deepEqual(validateSchema(graphSchema, approvalGraph), []);
    assert.deepEqual(validateSchema(graphSchema, policyGraph), []);
    assert.deepEqual(validateSchema(graphSchema, contextGraph), []);
    assert.deepEqual(validateSchema(graphSchema, memoryGraph), []);
    assert.deepEqual(validateSchema(graphSchema, secretGraph), []);
    assert.deepEqual(validateSchema(graphSchema, ticketGraph), []);
    for (const payloads of examplePayloads) {
      assert.deepEqual(validateSchema(astSchema, payloads.ast), []);
      assert.deepEqual(validateSchema(checkSchema, payloads.check), []);
      assert.deepEqual(validateSchema(graphSchema, payloads.graph), []);
    }
  });

  it("rejects empty structural graph strings in the schema", () => {
    const graphSchema = readJson(GRAPH_SCHEMA);
    const graph = {
      schema_version: "intent.graph.v0",
      ast_schema_version: "intent.ast.v0",
      source: "",
      package: "",
      ok: true,
      diagnostics: [],
      nodes: [
        { id: "", kind: "Type", label: "", span: testSpan(1), data: { definition: null } },
      ],
      edges: [
        { from: "", to: "", kind: "declares" },
      ],
    };
    const blankBaseNode = { id: "", kind: "", label: "", span: testSpan(2), data: {} };
    const baseNodeErrors = [];
    const diagnosticErrors = [];
    const trustErrors = [];
    validateAgainst(graphSchema.$defs.base_node, blankBaseNode, graphSchema, "$defs.base_node", baseNodeErrors);
    validateAgainst(graphSchema.$defs.diagnostic, { severity: "error", code: "", message: "", span: testSpan(3) }, graphSchema, "$defs.diagnostic", diagnosticErrors);
    validateAgainst(graphSchema.$defs.trust, { zone: "trusted", source: "", argument: "" }, graphSchema, "$defs.trust", trustErrors);
    const errors = validateSchema(graphSchema, graph);

    assert(errors.includes("$.source length must be >= 1"));
    assert(errors.includes("$.package length must be >= 1"));
    assert(errors.includes("$.edges[0].from length must be >= 1"));
    assert(errors.includes("$.edges[0].to length must be >= 1"));
    assert(baseNodeErrors.includes("$defs.base_node.id length must be >= 1"));
    assert(baseNodeErrors.includes("$defs.base_node.kind length must be >= 1"));
    assert(baseNodeErrors.includes("$defs.base_node.label length must be >= 1"));
    assert(diagnosticErrors.includes("$defs.diagnostic.code length must be >= 1"));
    assert(diagnosticErrors.includes("$defs.diagnostic.message length must be >= 1"));
    assert(trustErrors.includes("$defs.trust.source length must be >= 1"));
    assert(trustErrors.includes("$defs.trust.argument length must be >= 1"));
  });

  it("requires source offsets in the schemas", () => {
    const astSchema = readJson(AST_SCHEMA);
    const checkSchema = readJson(CHECK_SCHEMA);
    const graphSchema = readJson(GRAPH_SCHEMA);
    const astErrors = [];
    const checkErrors = [];
    const graphErrors = [];

    validateAgainst(astSchema.$defs.position, { line: 1, column: 1 }, astSchema, "$defs.position", astErrors);
    validateAgainst(checkSchema.$defs.position, { line: 1, column: 1 }, checkSchema, "$defs.position", checkErrors);
    validateAgainst(graphSchema.$defs.position, { line: 1, column: 1 }, graphSchema, "$defs.position", graphErrors);

    assert(astErrors.includes("$defs.position.offset is required"));
    assert(checkErrors.includes("$defs.position.offset is required"));
    assert(graphErrors.includes("$defs.position.offset is required"));
  });

  it("requires output type spans in AST and graph schemas", () => {
    const astSchema = readJson(AST_SCHEMA);
    const graphSchema = readJson(GRAPH_SCHEMA);
    const astGoalErrors = [];
    const astStepErrors = [];
    const goalErrors = [];
    const stepErrors = [];
    const completionErrors = [];

    validateAgainst(astSchema.$defs.goal, {
      kind: "Goal",
      name: "demo",
      title: null,
      parameters: [],
      outputType: null,
      context: [],
      capabilities: [],
      memory: [],
      steps: [],
      verify: [],
      invariants: [],
      rawBlocks: [],
      span: testSpan(1),
    }, astSchema, "$defs.goal", astGoalErrors);
    validateAgainst(astSchema.$defs.step, {
      kind: "Step",
      name: "patch",
      parameters: [],
      outputType: null,
      effects: [],
      requirements: [],
      checkpoints: [],
      approvals: [],
      timeouts: [],
      retries: [],
      memoryAccesses: [],
      span: testSpan(2),
    }, astSchema, "$defs.step", astStepErrors);
    validateAgainst(graphSchema.$defs.goal_node, {
      id: "goal:demo",
      kind: "Goal",
      label: "demo",
      span: testSpan(1),
      data: { title: null, parameters: [], outputType: null },
    }, graphSchema, "$defs.goal_node", goalErrors);
    validateAgainst(graphSchema.$defs.step_node, {
      id: "goal:demo:step:patch",
      kind: "Step",
      label: "patch",
      span: testSpan(2),
      data: { inputs: [], outputType: null, effects: [], requirements: [], checkpoints: [], approvals: [], timeouts: [], retries: [], memoryAccesses: [] },
    }, graphSchema, "$defs.step_node", stepErrors);
    validateAgainst(graphSchema.$defs.completion_node, {
      id: "goal:demo:completion",
      kind: "Completion",
      label: "demo",
      span: testSpan(3),
      data: { outputType: null },
    }, graphSchema, "$defs.completion_node", completionErrors);

    assert(astGoalErrors.includes("$defs.goal.outputTypeSpan is required"));
    assert(astStepErrors.includes("$defs.step.outputTypeSpan is required"));
    assert(goalErrors.includes("$defs.goal_node.data.outputTypeSpan is required"));
    assert(stepErrors.includes("$defs.step_node.data.outputTypeSpan is required"));
    assert(completionErrors.includes("$defs.completion_node.data.outputTypeSpan is required"));
  });

  it("rejects empty structural AST and check strings in schemas", () => {
    const astSchema = readJson(AST_SCHEMA);
    const checkSchema = readJson(CHECK_SCHEMA);
    const ast = {
      schema_version: "intent.ast.v0",
      source: "",
      package: {
        kind: "Package",
        name: "",
        span: testSpan(1),
      },
      imports: [],
      types: [],
      goals: [],
      span: { ...testSpan(1), file: "" },
    };
    const parameterErrors = [];
    const importErrors = [];
    const check = {
      schema_version: "intent.check.v0",
      ok: false,
      diagnostics: [
        {
          severity: "error",
          code: "",
          message: "",
          span: { ...testSpan(1), file: "" },
          action: "",
        },
      ],
    };
    const astErrors = validateSchema(astSchema, ast);
    const checkErrors = validateSchema(checkSchema, check);
    validateAgainst(
      astSchema.$defs.parameter,
      { name: "", type: "", span: testSpan(2) },
      astSchema,
      "$defs.parameter",
      parameterErrors,
    );
    validateAgainst(
      astSchema.$defs.import,
      { kind: "Import", path: "", span: testSpan(2) },
      astSchema,
      "$defs.import",
      importErrors,
    );

    assert(astErrors.includes("$.source length must be >= 1"));
    assert(astErrors.includes("$.package.name length must be >= 1"));
    assert(astErrors.includes("$.span.file length must be >= 1"));
    assert(importErrors.includes("$defs.import.path length must be >= 1"));
    assert(parameterErrors.includes("$defs.parameter.name length must be >= 1"));
    assert(parameterErrors.includes("$defs.parameter.type must match exactly one schema, matched 0"));
    assert(checkErrors.includes("$.diagnostics[0].code length must be >= 1"));
    assert(checkErrors.includes("$.diagnostics[0].message length must be >= 1"));
    assert(checkErrors.includes("$.diagnostics[0].span.file length must be >= 1"));
    assert(checkErrors.includes("$.diagnostics[0].action must match exactly one schema, matched 0"));
  });
});
