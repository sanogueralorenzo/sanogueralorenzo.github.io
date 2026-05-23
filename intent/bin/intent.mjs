#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";
import process from "node:process";

const VERSION = "intent.static.v0";
const AST_SCHEMA_VERSION = "intent.ast.v0";
const CHECK_SCHEMA_VERSION = "intent.check.v0";
const GRAPH_SCHEMA_VERSION = "intent.graph.v0";
const sourceLineOffsets = new Map();
const BUILTIN_TYPES = new Set([
  "String",
  "Bool",
  "Int",
  "Float",
  "List",
  "Map",
  "Record",
  "Goal",
  "Context",
  "Capability",
  "Effect",
  "Step",
  "Evidence",
  "Assumption",
  "Decision",
  "Verified",
  "Checkpoint",
  "Provenance",
  "SecretRef",
]);
const GRAPH_NODE_KINDS = new Set([
  "Approval",
  "Capability",
  "Check",
  "Checkpoint",
  "Completion",
  "Context",
  "Effect",
  "Goal",
  "Input",
  "Invariant",
  "Memory",
  "Policy",
  "Step",
  "Type",
]);
const GRAPH_EDGE_KINDS = new Set([
  "authorizes",
  "approves",
  "checkpoints",
  "completes",
  "constrains",
  "data",
  "declares",
  "gates",
  "guards",
  "informs",
  "plans",
  "precedes",
  "produces",
  "requests",
  "requires",
  "retries",
  "supplies",
  "timeouts",
  "verifies",
]);
const TRUST_ZONES = new Set(["trusted", "untrusted", "unknown"]);

function usage() {
  return [
    "Usage: node intent/bin/intent.mjs <parse|check|graph> <file.intent> [--json]",
    "",
    "Commands:",
    "  parse   Parse Intent source and emit AST JSON.",
    "  check   Run static checks and emit diagnostics.",
    "  graph   Emit a machine-readable execution graph.",
  ].join("\n");
}

function main(argv) {
  const [command, file] = argv;
  if (!command || command === "--help" || command === "-h") {
    console.log(usage());
    return 0;
  }
  if (!["parse", "check", "graph"].includes(command)) {
    console.error(`intent: unknown command '${command}'`);
    console.error(usage());
    return 2;
  }
  if (!file) {
    console.error("intent: missing source file");
    console.error(usage());
    return 2;
  }

  let source;
  try {
    source = fs.readFileSync(file, "utf8");
  } catch (error) {
    console.error(`intent: failed to read ${file}: ${error.message}`);
    return 2;
  }

  try {
    const ast = parseIntent(source, file);
    if (command === "parse") {
      printJson(ast);
      return 0;
    }

    const diagnostics = checkIntent(ast);
    if (command === "check") {
      printJson({
        schema_version: CHECK_SCHEMA_VERSION,
        ok: diagnostics.length === 0,
        diagnostics,
      });
      return diagnostics.length === 0 ? 0 : 1;
    }

    const graph = buildGraph(ast, diagnostics);
    printJson(graph);
    return diagnostics.length === 0 ? 0 : 1;
  } catch (error) {
    const diagnostic = error.diagnostic ?? {
      code: "INTENT_PARSE_ERROR",
      severity: "error",
      message: error.message,
      span: span(file, 1, 1),
    };
    printJson({
      schema_version: CHECK_SCHEMA_VERSION,
      ok: false,
      diagnostics: [diagnostic],
    });
    return 1;
  }
}

function printJson(value) {
  process.stdout.write(`${JSON.stringify(value, null, 2)}\n`);
}

function isPlainObject(value) {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function isSpan(value) {
  return isPlainObject(value)
    && typeof value.file === "string"
    && isPosition(value.start)
    && isPosition(value.end);
}

function isPosition(value) {
  return isPlainObject(value)
    && Number.isInteger(value.line)
    && value.line >= 1
    && Number.isInteger(value.column)
    && value.column >= 1;
}

function graphSourceFile(graph) {
  return typeof graph.source === "string" ? graph.source : "graph";
}

function parseIntent(source, file) {
  const lines = source.split(/\r?\n/);
  sourceLineOffsets.set(path.normalize(file), computeLineOffsets(source));
  const root = {
    schema_version: AST_SCHEMA_VERSION,
    source: path.normalize(file),
    package: null,
    types: [],
    goals: [],
    span: span(file, 1, 1, lines.length, lastColumn(lines)),
  };

  let index = 0;
  while (index < lines.length) {
    const raw = lines[index];
    const line = stripComment(raw).trim();
    const lineNumber = index + 1;
    if (!line) {
      index += 1;
      continue;
    }

    const packageMatch = line.match(/^package\s+([a-z][a-z0-9_]*(?:\.[a-z][a-z0-9_]*)*)$/);
    if (packageMatch) {
      root.package = {
        kind: "Package",
        name: packageMatch[1],
        span: lineSpan(file, lineNumber, raw),
      };
      index += 1;
      continue;
    }

    if (line.startsWith("type ")) {
      if (line.includes("{")) {
        const parsed = collectBlock(lines, index, file);
        root.types.push(parseTypeDecl(parsed.header, file, parsed.startLine, raw, parsed.body.map((entry) => entry.text).join("\n")));
        index = parsed.nextIndex;
        continue;
      }
      root.types.push(parseTypeDecl(line, file, lineNumber, raw));
      index += 1;
      continue;
    }

    if (line.startsWith("goal ")) {
      const parsed = collectBlock(lines, index, file);
      root.goals.push(parseGoal(parsed.header, parsed.body, file, parsed.startLine, parsed.endLine));
      index = parsed.nextIndex;
      continue;
    }

    throw parseError(file, lineNumber, raw, `unexpected top-level statement '${line}'`);
  }

  if (!root.package) {
    root.package = {
      kind: "Package",
      name: "main",
      implicit: true,
      span: span(file, 1, 1),
    };
  }

  return root;
}

function parseTypeDecl(line, file, lineNumber, raw, body = null) {
  const match = line.match(/^type\s+([A-Z][A-Za-z0-9_]*)(?:\s*=\s*(.*))?$/);
  if (!match) {
    throw parseError(file, lineNumber, raw, `invalid type declaration '${line}'`);
  }
  return {
    kind: "Type",
    name: match[1],
    definition: body ?? match[2] ?? null,
    span: lineSpan(file, lineNumber, raw),
  };
}

function parseGoal(header, bodyLines, file, startLine, endLine) {
  const named = header.match(/^goal\s+([a-z][a-z0-9_]*)\s*\(([^)]*)\)\s*(?:->\s*([A-Za-z][A-Za-z0-9_<>, ]*))?$/);
  const quoted = header.match(/^goal\s+"([^"]+)"$/);
  if (!named && !quoted) {
    throw parseError(file, startLine, header, `invalid goal declaration '${header}'`);
  }
  const outputType = named && named[3] ? named[3].trim() : null;

  const goal = {
    kind: "Goal",
    name: named ? named[1] : slugify(quoted[1]),
    title: named ? null : quoted[1],
    parameters: named ? parseParameters(named[2], file, startLine, header) : [],
    outputType,
    outputTypeSpan: parseOutputTypeSpan(outputType, file, startLine, header),
    context: [],
    capabilities: [],
    memory: [],
    steps: [],
    verify: [],
    invariants: [],
    rawBlocks: [],
    span: span(file, startLine, 1, endLine, 1),
  };

  let index = 0;
  while (index < bodyLines.length) {
    const entry = bodyLines[index];
    const line = stripComment(entry.text).trim();
    if (!line) {
      index += 1;
      continue;
    }

    const blockName = firstWord(line);
    if (["context", "capabilities", "capability", "memory", "plan", "verify", "invariant", "invariants"].includes(blockName) && line.includes("{")) {
      const block = collectInlineBlock(bodyLines, index, file);
      parseGoalBlock(goal, blockName, line.replace(/\s*\{\s*$/, ""), block.body, file, block.startLine, block.endLine);
      index = block.nextIndex;
      continue;
    }

    if (line.startsWith("context ")) {
      goal.context.push(parseContextSource(line.slice("context ".length), file, entry.lineNumber, entry.text));
      index += 1;
      continue;
    }

    if (line.startsWith("capability ")) {
      goal.capabilities.push(parseCapabilityLine(line, file, entry.lineNumber, entry.text));
      index += 1;
      continue;
    }

    goal.rawBlocks.push(statementNode("RawGoalStatement", line, file, entry.lineNumber, entry.text));
    index += 1;
  }

  return goal;
}

function parseGoalBlock(goal, blockName, header, body, file, startLine, endLine) {
  const normalized = blockName === "capabilities" ? "capability" : blockName === "invariants" ? "invariant" : blockName;
  goal.rawBlocks.push({
    kind: "Block",
    name: normalized,
    header,
    span: span(file, startLine, 1, endLine, 1),
  });

  if (normalized === "context") {
    for (const line of meaningfulLines(body)) {
      goal.context.push(parseContextSource(line.text, file, line.lineNumber, line.raw));
    }
    return;
  }

  if (normalized === "capability") {
    if (header !== "capability" && header.startsWith("capability ")) {
      const name = header.slice("capability ".length).trim();
      const lines = meaningfulLines(body);
      const capability = {
        kind: "Capability",
        family: capabilityFamily(name),
        action: null,
        name,
        constraints: lines.map((line) => line.text),
        grants: lines.map((line) => parseCapabilityGrant(line.text, lineSpan(file, line.lineNumber, line.raw))).filter(Boolean),
        approvalRequired: hasApprovalRequired(lines),
        span: span(file, startLine, 1, endLine, 1),
      };
      goal.capabilities.push(capability);
      return;
    }
    for (const line of meaningfulLines(body)) {
      goal.capabilities.push(parseCapabilityLine(line.text, file, line.lineNumber, line.raw));
    }
    return;
  }

  if (normalized === "memory") {
    const headerParts = header.split(/\s+/);
    const lines = meaningfulLines(body);
    goal.memory.push({
      kind: "Memory",
      scope: headerParts[1] ?? "unspecified",
      name: headerParts[2] ?? null,
      retention: lines.filter((line) => line.text.startsWith("retain ")).map((line) => line.text),
      retentionRules: lines.filter((line) => line.text.startsWith("retain ")).map((line) => parseRetentionRule(line, file)),
      statements: lines.map((line) => line.text),
      span: span(file, startLine, 1, endLine, 1),
    });
    return;
  }

  if (normalized === "plan") {
    goal.steps.push(...parsePlan(body, file));
    return;
  }

  if (normalized === "verify") {
    for (const line of meaningfulLines(body)) {
      if (line.text.startsWith("require ")) {
        goal.verify.push(statementNode("Require", line.text.slice("require ".length), file, line.lineNumber, line.raw));
      }
    }
    return;
  }

  if (normalized === "invariant") {
    for (const line of meaningfulLines(body)) {
      if (line.text.startsWith("require ")) {
        goal.invariants.push(statementNode("Require", line.text.slice("require ".length), file, line.lineNumber, line.raw));
      } else if (line.text.startsWith("deny ")) {
        goal.invariants.push(statementNode("Deny", line.text.slice("deny ".length), file, line.lineNumber, line.raw));
      }
    }
  }
}

function parsePlan(body, file) {
  const steps = [];
  let index = 0;
  while (index < body.length) {
    const entry = body[index];
    const line = stripComment(entry.text).trim();
    if (!line) {
      index += 1;
      continue;
    }

    if (line.startsWith("step ") && line.includes("{")) {
      const block = collectInlineBlock(body, index, file);
      steps.push(parseStep(line.replace(/\s*\{\s*$/, ""), block.body, file, block.startLine, block.endLine));
      index = block.nextIndex;
      continue;
    }

    if (line.startsWith("step ")) {
      steps.push(parseStep(line, [], file, entry.lineNumber, entry.lineNumber));
      index += 1;
      continue;
    }

    index += 1;
  }
  return steps;
}

function parseStep(header, body, file, startLine, endLine) {
  const match = header.match(/^step\s+([A-Za-z][A-Za-z0-9_]*)\s*(?:\(([^)]*)\))?\s*(?:->\s*([A-Za-z][A-Za-z0-9_<>, ]*))?/);
  if (!match) {
    throw parseError(file, startLine, header, `invalid step declaration '${header}'`);
  }
  const outputType = match[3] ? match[3].trim() : null;
  const effects = [];
  const requirements = [];
  const checkpoints = [];
  const approvals = [];
  const timeouts = [];
  const retries = [];
  if (outputType) {
    const effectOutput = outputType.match(/^Effect<\s*([A-Za-z][A-Za-z0-9_.]*)/);
    if (effectOutput) {
      effects.push(parseEffectUse(effectOutput[1], file, startLine, header));
    }
  }
  for (const line of meaningfulLines(body)) {
    if (line.text.startsWith("effect ")) {
      effects.push(parseEffectUse(line.text.slice("effect ".length), file, line.lineNumber, line.raw));
    }
    if (line.text.startsWith("require ")) {
      requirements.push(statementNode("Require", line.text.slice("require ".length), file, line.lineNumber, line.raw));
    }
    if (line.text.startsWith("checkpoint ")) {
      checkpoints.push(parseCheckpointStatement(line, file));
    }
    if (line.text.startsWith("approval ")) {
      approvals.push(parseApprovalStatement(line, file));
    }
    if (line.text.startsWith("timeout ")) {
      timeouts.push(parsePolicyStatement("Timeout", line, file, "timeout "));
    }
    if (line.text.startsWith("retry ")) {
      retries.push(parsePolicyStatement("Retry", line, file, "retry "));
    }
  }
  return {
    kind: "Step",
    name: match[1],
    parameters: parseParameters(match[2] ?? "", file, startLine, header),
    outputType,
    outputTypeSpan: parseOutputTypeSpan(outputType, file, startLine, header),
    effects,
    requirements,
    checkpoints,
    approvals,
    timeouts,
    retries,
    span: span(file, startLine, 1, endLine, 1),
  };
}

function parseCapabilityLine(text, file, lineNumber, raw) {
  const normalized = text.replace(/^capability\s+/, "").trim();
  const dotted = normalized.match(/^([a-z][a-z0-9_]*)(?:\.([a-z][a-z0-9_]*))?/);
  const bare = normalized.match(/^([a-z][a-z0-9_]*)\s*\(/);
  const family = dotted?.[1] ?? bare?.[1] ?? firstWord(normalized);
  const action = dotted?.[2] ?? null;
  return {
    kind: "Capability",
    family,
    action,
    name: normalized,
    constraints: [normalized],
    grants: [parseCapabilityGrant(normalized, lineSpan(file, lineNumber, raw))].filter(Boolean),
    approvalRequired: /\bapproval\s*:\s*required\b|\bapproval\s+required\b/.test(normalized),
    span: lineSpan(file, lineNumber, raw),
  };
}

function parseContextSource(text, file, lineNumber, raw) {
  const source = text.match(/^([a-z][a-z0-9_]*)\s*\(/)?.[1] ?? firstWord(text);
  const parsedArgs = parseCallArgs(text, file, lineNumber, raw);
  return {
    kind: "ContextSource",
    value: text,
    source,
    args: parsedArgs.values,
    argKinds: parsedArgs.kinds,
    argSpans: parsedArgs.spans,
    expression: text,
    trust: contextTrust(source),
    span: lineSpan(file, lineNumber, raw),
  };
}

function parseEffectUse(text, file, lineNumber, raw) {
  const parsedArgs = parseCallArgs(text, file, lineNumber, raw);
  const name = text.match(/^([A-Za-z][A-Za-z0-9_.]*)/)?.[1] ?? text;
  return {
    kind: "EffectUse",
    name,
    family: effectFamily(name),
    action: effectAction(name),
    args: parsedArgs.values,
    argKinds: parsedArgs.kinds,
    argSpans: parsedArgs.spans,
    expression: text,
    span: lineSpan(file, lineNumber, raw),
  };
}

function parseRetentionRule(line, file) {
  const match = line.text.match(/^retain\s+(.+?)\s+until\s+(.+)$/);
  const subject = match?.[1]?.trim() ?? null;
  const until = match?.[2]?.trim() ?? null;
  return {
    subject: subject ? spannedText(subject, line, file) : null,
    until: until ? spannedText(until, line, file) : null,
    raw: line.text,
    span: lineSpan(file, line.lineNumber, line.raw),
  };
}

function parseCheckpointStatement(line, file) {
  return statementNode("Checkpoint", unquote(line.text.slice("checkpoint ".length)), file, line.lineNumber, line.raw);
}

function parseApprovalStatement(line, file) {
  return statementNode("Approval", unquote(line.text.slice("approval ".length)), file, line.lineNumber, line.raw);
}

function parsePolicyStatement(kind, line, file, prefix) {
  return statementNode(kind, unquote(line.text.slice(prefix.length)), file, line.lineNumber, line.raw);
}

function checkIntent(ast) {
  const diagnostics = [];
  const declaredTypes = new Map();
  for (const typeDecl of ast.types) {
    if (declaredTypes.has(typeDecl.name)) {
      diagnostics.push(error("INTENT_NAME_DUPLICATE", `type '${typeDecl.name}' is already declared.`, typeDecl.span, {
        name: typeDecl.name,
        previous_span: declaredTypes.get(typeDecl.name).span,
      }));
    } else {
      declaredTypes.set(typeDecl.name, typeDecl);
    }
  }

  if (ast.goals.length === 0) {
    diagnostics.push(error("INTENT_GOAL_MISSING", "Intent source must declare at least one goal.", ast.span));
  }

  const goalNames = new Map();
  for (const goal of ast.goals) {
    if (goalNames.has(goal.name)) {
      diagnostics.push(error("INTENT_NAME_DUPLICATE", `goal '${goal.name}' is already declared.`, goal.span, {
        name: goal.name,
        previous_span: goalNames.get(goal.name).span,
      }));
    } else {
      goalNames.set(goal.name, goal);
    }

    const hasEffects = goal.steps.some((step) => step.effects.length > 0) || goal.capabilities.some((capability) => {
      return capability.constraints.some((constraint) => /\b(write|run|push|deploy|commit|update)\b/.test(constraint))
        || ["shell", "git", "deploy", "ticket"].includes(capability.family);
    });
    if (hasEffects && goal.verify.length === 0) {
      diagnostics.push(error("INTENT_VERIFY_MISSING", `goal '${goal.name}' uses effects but has no verify block with require statements.`, goal.span));
    }

    validateUnsupportedSyntax(goal, diagnostics);
    validateMemory(goal, diagnostics);
    validateContextSources(goal, diagnostics);

    validateGoalTypes(goal, declaredTypes, diagnostics);
    validateStepBindings(goal, diagnostics);
    validateGoalCompletionType(goal, diagnostics);
    validateStepPolicies(goal, diagnostics);
    validateStepCheckpoints(goal, diagnostics);
    validateStepApprovals(goal, diagnostics);
    validateVerifyRequirements(goal, diagnostics);
    validateApprovalRequirements(goal, diagnostics);

    const capabilities = goal.capabilities.map((capability) => capability.family);
    for (const step of goal.steps) {
      for (const effect of step.effects) {
        if (!isEffectAuthorized(effect, goal.capabilities)) {
          diagnostics.push(error("INTENT_EFFECT_UNDECLARED", `effect '${effect.name}' is not authorized by goal capabilities.`, effect.span, {
            effect: effect.name,
            required_family: effect.family,
            declared_capabilities: capabilities,
          }));
          continue;
        }

        const trustFlow = getTrustFlowDiagnostic(effect);
        if (trustFlow) {
          diagnostics.push(error("INTENT_TRUST_FLOW_UNSAFE", trustFlow.message, effectArgumentSpan(effect, trustFlow), {
            effect: effect.name,
            family: effect.family,
            action: effect.action,
            argument: trustFlow.argument,
            value: trustFlow.value,
            trust: trustFlow.trust,
          }));
          continue;
        }

        const denial = getCapabilityDenial(effect, goal.capabilities);
        if (denial) {
          diagnostics.push(error("INTENT_CAPABILITY_DENIED", denial.message, effectArgumentSpan(effect, denial), {
            effect: effect.name,
            family: effect.family,
            action: effect.action,
            argument: denial.argument,
            value: denial.value,
            allowed: denial.allowed,
          }));
          continue;
        }

        const invariantViolation = getInvariantViolation(effect, goal.invariants, goal.context);
        if (invariantViolation) {
          diagnostics.push(error("INTENT_INVARIANT_VIOLATION", invariantViolation.message, invariantViolation.invariant.span, {
            invariant: invariantViolation.invariant.value,
            effect: effect.name,
            family: effect.family,
            action: effect.action,
            argument: invariantViolation.argument,
            value: invariantViolation.value,
            effect_span: effectArgumentSpan(effect, invariantViolation),
          }));
        }
      }
    }
  }

  return diagnostics;
}

function validateApprovalRequirements(goal, diagnostics) {
  for (const step of goal.steps) {
    for (const effect of step.effects) {
      const approvalCapability = approvalRequiredCapability(effect, goal.capabilities);
      if (!approvalCapability || step.approvals.length > 0) {
        continue;
      }
      diagnostics.push(error("INTENT_APPROVAL_MISSING", `effect '${effect.name}' requires a step approval gate.`, effect.span, {
        effect: effect.name,
        family: effect.family,
        action: effect.action,
        capability: approvalCapability.name,
        step: step.name,
      }));
    }
  }
}

function validateContextSources(goal, diagnostics) {
  for (const context of goal.context) {
    const access = contextAccess(context);
    if (!access) {
      continue;
    }

    const denial = !isEffectAuthorized(access, goal.capabilities)
      ? {
          message: `context '${context.expression}' is not authorized by goal capabilities.`,
          argument: effectArgument(access)?.key ?? "source",
          value: effectArgument(access)?.value ?? context.expression,
          allowed: [],
        }
      : getCapabilityDenial(access, goal.capabilities);

    if (denial) {
      diagnostics.push(error("INTENT_CONTEXT_UNDECLARED", `context '${context.expression}' must be covered by a matching read capability.`, effectArgumentSpan(access, denial), {
        context: context.expression,
        source: context.source,
        family: access.family,
        action: access.action,
        argument: denial.argument,
        value: denial.value,
        allowed: denial.allowed,
      }));
    }
  }
}

function validateUnsupportedSyntax(goal, diagnostics) {
  for (const item of goal.rawBlocks) {
    if (item.kind !== "RawGoalStatement") {
      continue;
    }
    diagnostics.push(error("INTENT_UNSUPPORTED_SYNTAX", `unsupported goal statement '${item.value}'.`, item.span, {
      syntax: item.value,
      goal: goal.name,
    }));
  }
}

function validateMemory(goal, diagnostics) {
  for (const memory of goal.memory) {
    const retentionRules = memory.retentionRules ?? [];
    if (retentionRules.length === 0) {
      diagnostics.push(error("INTENT_MEMORY_UNSCOPED", `memory '${memory.name ?? memory.scope}' must declare retention.`, memory.span, {
        memory: memory.name ?? memory.scope,
        scope: memory.scope,
      }));
      continue;
    }

    for (const retention of retentionRules) {
      if (!retention.subject?.raw || !retention.until?.raw || !isSupportedRetentionUntil(retention.until.raw)) {
        diagnostics.push(error("INTENT_MEMORY_RETENTION_INVALID", `memory '${memory.name ?? memory.scope}' has invalid retention rule '${retention.raw}'.`, retention.span, {
          memory: memory.name ?? memory.scope,
          scope: memory.scope,
          retention: retention.raw,
          until: retention.until?.raw ?? null,
        }));
      }
    }
  }
}

function isSupportedRetentionUntil(value) {
  const normalized = value.trim();
  return normalized === "goal_complete"
    || normalized === "goal.completed"
    || /^[1-9][0-9]*(?:s|m|h|d)$/.test(normalized);
}

function validateGoalTypes(goal, declaredTypes, diagnostics) {
  const seenParameters = new Map();
  for (const parameter of goal.parameters) {
    if (seenParameters.has(parameter.name)) {
      diagnostics.push(error("INTENT_NAME_DUPLICATE", `parameter '${parameter.name}' is already declared in goal '${goal.name}'.`, parameter.span, {
        name: parameter.name,
        previous_span: seenParameters.get(parameter.name).span,
      }));
    }
    seenParameters.set(parameter.name, parameter);
    validateTypeRef(parameter.type, parameter.span, declaredTypes, diagnostics);
  }
  validateTypeRef(goal.outputType, goal.outputTypeSpan ?? goal.span, declaredTypes, diagnostics);

  const stepNames = new Map();
  for (const step of goal.steps) {
    if (stepNames.has(step.name)) {
      diagnostics.push(error("INTENT_NAME_DUPLICATE", `step '${step.name}' is already declared in goal '${goal.name}'.`, step.span, {
        name: step.name,
        previous_span: stepNames.get(step.name).span,
      }));
    } else {
      stepNames.set(step.name, step);
    }

    const parameterNames = new Map();
    for (const parameter of step.parameters) {
      if (parameterNames.has(parameter.name)) {
        diagnostics.push(error("INTENT_NAME_DUPLICATE", `parameter '${parameter.name}' is already declared in step '${step.name}'.`, parameter.span, {
          name: parameter.name,
          previous_span: parameterNames.get(parameter.name).span,
        }));
      }
      parameterNames.set(parameter.name, parameter);
      validateTypeRef(parameter.type, parameter.span, declaredTypes, diagnostics);
    }
    validateTypeRef(step.outputType, step.outputTypeSpan ?? step.span, declaredTypes, diagnostics);
  }
}

function validateTypeRef(typeRef, nodeSpan, declaredTypes, diagnostics) {
  if (!typeRef) {
    return;
  }
  for (const name of extractTypeNames(typeRef)) {
    if (!BUILTIN_TYPES.has(name) && !declaredTypes.has(name)) {
      diagnostics.push(error("INTENT_TYPE_UNRESOLVED", `type '${name}' is not declared.`, nodeSpan, {
        type: name,
      }));
    }
  }
}

function validateStepBindings(goal, diagnostics) {
  const availableTypes = new Set(goal.parameters.map((parameter) => normalizeTypeRef(parameter.type)).filter(Boolean));
  for (const step of goal.steps) {
    for (const parameter of step.parameters) {
      const parameterType = normalizeTypeRef(parameter.type);
      if (parameterType && !availableTypes.has(parameterType)) {
        diagnostics.push(error("INTENT_STEP_INPUT_UNRESOLVED", `step '${step.name}' input '${parameter.name}' requires '${parameterType}' before any prior step produces it.`, step.span, {
          step: step.name,
          parameter: parameter.name,
          type: parameterType,
        }));
      }
    }
    const outputType = normalizeTypeRef(step.outputType);
    if (outputType) {
      availableTypes.add(outputType);
    }
  }
}

function validateGoalCompletionType(goal, diagnostics) {
  const expectedType = normalizeTypeRef(goal.outputType);
  const finalStep = goal.steps.at(-1);
  const actualType = normalizeTypeRef(finalStep?.outputType);
  if (!expectedType || !finalStep || !actualType || expectedType === actualType) {
    return;
  }
  diagnostics.push(error("INTENT_TYPE_MISMATCH", `goal '${goal.name}' declares output '${expectedType}' but final step '${finalStep.name}' produces '${actualType}'.`, finalStep.outputTypeSpan ?? finalStep.span, {
    goal: goal.name,
    step: finalStep.name,
    expected: expectedType,
    actual: actualType,
  }));
}

function validateStepPolicies(goal, diagnostics) {
  for (const step of goal.steps) {
    for (const timeout of step.timeouts) {
      if (!isSupportedPolicyDuration(timeout.value)) {
        diagnostics.push(error("INTENT_POLICY_INVALID", `step '${step.name}' has invalid timeout policy '${timeout.value}'.`, timeout.span, {
          step: step.name,
          policyKind: "timeout",
          policy: timeout.value,
        }));
      }
    }
    for (const retry of step.retries) {
      if (!isSupportedRetryPolicy(retry.value)) {
        diagnostics.push(error("INTENT_POLICY_INVALID", `step '${step.name}' has invalid retry policy '${retry.value}'.`, retry.span, {
          step: step.name,
          policyKind: "retry",
          policy: retry.value,
        }));
      }
    }
  }
}

function isSupportedPolicyDuration(value) {
  return /^[1-9][0-9]*(?:s|m|h|d)$/.test(value.trim());
}

function isSupportedRetryPolicy(value) {
  return /^max\s+[1-9][0-9]*$/.test(value.trim());
}

function validateStepCheckpoints(goal, diagnostics) {
  for (const step of goal.steps) {
    for (const checkpoint of step.checkpoints) {
      if (!checkpoint.value.trim()) {
        diagnostics.push(error("INTENT_CHECKPOINT_INVALID", `step '${step.name}' has an empty checkpoint label.`, checkpoint.span, {
          step: step.name,
          checkpoint: checkpoint.value,
        }));
      }
    }
  }
}

function validateStepApprovals(goal, diagnostics) {
  for (const step of goal.steps) {
    for (const approval of step.approvals) {
      if (!approval.value.trim()) {
        diagnostics.push(error("INTENT_APPROVAL_INVALID", `step '${step.name}' has an empty approval gate label.`, approval.span, {
          step: step.name,
          approval: approval.value,
        }));
      }
    }
  }
}

function validateVerifyRequirements(goal, diagnostics) {
  for (const requirement of goal.verify) {
    const impureEffect = verificationImpureEffect(requirement);
    if (impureEffect) {
      diagnostics.push(error("INTENT_VERIFY_IMPURE", `verify requirement '${requirement.value}' uses side-effect call '${impureEffect.name}'.`, impureEffect.span, {
        requirement: requirement.value,
        effect: impureEffect.name,
        family: impureEffect.family,
        action: impureEffect.action,
      }));
      continue;
    }

    const effect = verificationEffect(requirement);
    if (!effect) {
      continue;
    }

    const denial = !isEffectAuthorized(effect, goal.capabilities)
      ? {
          message: `verify requirement '${requirement.value}' is not authorized by goal capabilities.`,
          argument: "command",
          value: effect.args.command,
          allowed: [],
        }
      : getCapabilityDenial(effect, goal.capabilities);

    if (denial) {
      diagnostics.push(error("INTENT_VERIFY_UNDECLARED", `verify requirement '${requirement.value}' must be declared by a matching capability grant.`, effectArgumentSpan(effect, denial), {
        requirement: requirement.value,
        family: effect.family,
        action: effect.action,
        argument: denial.argument,
        value: denial.value,
        allowed: denial.allowed,
      }));
    }
  }
}

function buildGraph(ast, diagnostics = checkIntent(ast)) {
  const nodes = [];
  const edges = [];

  for (const goal of ast.goals) {
    const goalId = `goal:${goal.name}`;
    for (const typeDecl of ast.types) {
      const typeId = `type:${typeDecl.name}`;
      if (!nodes.some((candidate) => candidate.id === typeId)) {
        nodes.push(node(typeId, "Type", typeDecl.name, typeDecl.span, {
          definition: typeDecl.definition,
        }));
      }
      edges.push(edge(typeId, goalId, "declares"));
    }

    nodes.push(node(goalId, "Goal", goal.name, goal.span, {
      title: goal.title,
      parameters: goal.parameters,
      outputType: goal.outputType,
      outputTypeSpan: goal.outputTypeSpan,
    }));

    const producersByType = new Map();
    for (const parameter of goal.parameters) {
      const inputId = `${goalId}:input:${parameter.name}`;
      nodes.push(node(inputId, "Input", parameter.name, parameter.span, {
        scope: "goal",
        type: parameter.type,
      }));
      edges.push(edge(inputId, goalId, "supplies"));
      addProducer(producersByType, parameter.type, inputId, parameter.span);
    }

    for (const [index, context] of goal.context.entries()) {
      const id = `${goalId}:context:${index}`;
      nodes.push(node(id, "Context", context.value, context.span, {
        source: context.source,
        args: context.args,
        argKinds: context.argKinds,
        argSpans: context.argSpans,
        expression: context.expression,
        trust: context.trust,
      }));
      edges.push(edge(id, goalId, "informs"));
      const access = contextAccess(context);
      if (access) {
        for (const [capabilityIndex, capability] of goal.capabilities.entries()) {
          if (isFamilyMatch(access.family, capability.family) && !getCapabilityDenial(access, [capability])) {
            edges.push(edge(`${goalId}:capability:${capabilityIndex}`, id, "authorizes"));
          }
        }
      }
    }

    for (const [index, capability] of goal.capabilities.entries()) {
      const id = `${goalId}:capability:${index}`;
      nodes.push(node(id, "Capability", capability.name, capability.span, {
        family: capability.family,
        action: capability.action,
        grants: capability.grants,
        approvalPolicy: capability.approvalRequired ? "required" : "none",
      }));
      edges.push(edge(id, goalId, "authorizes"));
    }

    for (const [index, memory] of goal.memory.entries()) {
      const id = `${goalId}:memory:${index}`;
      nodes.push(node(id, "Memory", memory.name ?? memory.scope, memory.span, {
        scope: memory.scope,
        retention: memory.retention,
        retentionRules: memory.retentionRules ?? [],
      }));
      edges.push(edge(goalId, id, "declares"));
    }

    let previousStepId = null;
    let lastStepId = null;
    const guardTargetIds = [];
    for (const [index, step] of goal.steps.entries()) {
      const id = `${goalId}:step:${step.name || index}`;
      nodes.push(node(id, "Step", step.name, step.span, {
        inputs: step.parameters,
        outputType: step.outputType,
        outputTypeSpan: step.outputTypeSpan,
        effects: step.effects.map((effect) => effect.name),
        requirements: step.requirements.map((requirement) => requirement.value),
        checkpoints: step.checkpoints.map((checkpoint) => checkpoint.value),
        approvals: step.approvals.map((approval) => approval.value),
        timeouts: step.timeouts.map((timeout) => timeout.value),
        retries: step.retries.map((retry) => retry.value),
      }));
      edges.push(edge(goalId, id, "plans"));
      if (previousStepId) {
        edges.push(edge(previousStepId, id, "precedes"));
      }
      previousStepId = id;
      lastStepId = id;
      const stepApprovalIds = [];

      for (const [requirementIndex, requirement] of step.requirements.entries()) {
        const requirementId = `${id}:requirement:${requirementIndex}`;
        nodes.push(node(requirementId, "Check", requirement.value, requirement.span, {
          scope: "step",
          ownerStep: step.name,
          assertion: requirement.kind,
          requirement: requirement.value,
        }));
        edges.push(edge(requirementId, goalId, "gates"));
        edges.push(edge(requirementId, id, "requires", {
          requirement: requirement.value,
        }));
        guardTargetIds.push(requirementId);
      }

      for (const parameter of step.parameters) {
        const stepInputId = `${id}:input:${parameter.name}`;
        nodes.push(node(stepInputId, "Input", parameter.name, parameter.span, {
          scope: "step",
          type: parameter.type,
        }));
        edges.push(edge(stepInputId, id, "requires", {
          parameter: parameter.name,
          type: normalizeTypeRef(parameter.type),
          targetSpan: parameter.span,
        }));

        const producer = latestProducer(producersByType, parameter.type);
        if (producer) {
          edges.push(edge(producer.id, stepInputId, "data", {
            parameter: parameter.name,
            type: normalizeTypeRef(parameter.type),
            sourceSpan: producer.span,
            targetSpan: parameter.span,
          }));
        }
      }

      for (const [approvalIndex, approval] of step.approvals.entries()) {
        const approvalId = `${id}:approval:${approvalIndex}`;
        nodes.push(node(approvalId, "Approval", approval.value, approval.span, {
          scope: "step",
          ownerStep: step.name,
          approval: approval.value,
        }));
        edges.push(edge(approvalId, id, "approves", {
          approval: approval.value,
        }));
        stepApprovalIds.push({
          id: approvalId,
          approval: approval.value,
        });
      }

      for (const [timeoutIndex, timeout] of step.timeouts.entries()) {
        const timeoutId = `${id}:timeout:${timeoutIndex}`;
        nodes.push(node(timeoutId, "Policy", timeout.value, timeout.span, {
          scope: "step",
          ownerStep: step.name,
          policyKind: "timeout",
          policy: timeout.value,
        }));
        edges.push(edge(timeoutId, id, "timeouts", {
          policy: timeout.value,
        }));
        guardTargetIds.push(timeoutId);
      }

      for (const [retryIndex, retry] of step.retries.entries()) {
        const retryId = `${id}:retry:${retryIndex}`;
        nodes.push(node(retryId, "Policy", retry.value, retry.span, {
          scope: "step",
          ownerStep: step.name,
          policyKind: "retry",
          policy: retry.value,
        }));
        edges.push(edge(retryId, id, "retries", {
          policy: retry.value,
        }));
        guardTargetIds.push(retryId);
      }

      for (const [checkpointIndex, checkpoint] of step.checkpoints.entries()) {
        const checkpointId = `${id}:checkpoint:${checkpointIndex}`;
        nodes.push(node(checkpointId, "Checkpoint", checkpoint.value, checkpoint.span, {
          scope: "step",
          ownerStep: step.name,
          checkpoint: checkpoint.value,
        }));
        edges.push(edge(id, checkpointId, "checkpoints", {
          checkpoint: checkpoint.value,
        }));
        guardTargetIds.push(checkpointId);
      }

      for (const [effectIndex, effectUse] of step.effects.entries()) {
        const effectId = `${id}:effect:${effectIndex}`;
        const approvalRequired = Boolean(approvalRequiredCapability(effectUse, goal.capabilities));
        nodes.push(node(effectId, "Effect", effectUse.name, effectUse.span, {
          family: effectUse.family,
          action: effectUse.action,
          args: effectUse.args,
          argKinds: effectUse.argKinds,
          argSpans: effectUse.argSpans,
          trust: effectTrust(effectUse),
          expression: effectUse.expression,
          approvalRequired,
        }));
        edges.push(edge(id, effectId, "requests"));
        if (approvalRequired) {
          for (const approval of stepApprovalIds) {
            edges.push(edge(approval.id, effectId, "approves", {
              approval: approval.approval,
            }));
          }
        }
        guardTargetIds.push(effectId);
        for (const [capabilityIndex, capability] of goal.capabilities.entries()) {
          if (isFamilyMatch(effectUse.family, capability.family) && !getCapabilityDenial(effectUse, [capability])) {
            edges.push(edge(`${goalId}:capability:${capabilityIndex}`, effectId, "authorizes"));
          }
        }
      }

      addProducer(producersByType, step.outputType, id, step.outputTypeSpan ?? step.span);
    }

    const completionId = `${goalId}:completion`;
    nodes.push(node(completionId, "Completion", goal.name, goal.span, {
      outputType: goal.outputType,
      outputTypeSpan: goal.outputTypeSpan,
    }));
    edges.push(edge(goalId, completionId, "completes"));
    if (lastStepId) {
      const finalStep = goal.steps.at(-1);
      edges.push(edge(lastStepId, completionId, "produces", {
        type: normalizeTypeRef(finalStep?.outputType),
        sourceSpan: finalStep?.outputTypeSpan ?? finalStep?.span,
        targetSpan: goal.outputTypeSpan ?? goal.span,
      }));
    }

    for (const [index, check] of goal.verify.entries()) {
      const id = `${goalId}:verify:${index}`;
      const effect = verificationEffect(check);
      nodes.push(node(id, "Check", check.value, check.span, effect ? {
        requirement: check.value,
        effect: {
          family: effect.family,
          action: effect.action,
          args: effect.args,
          argKinds: effect.argKinds,
          argSpans: effect.argSpans,
          trust: effectTrust(effect),
        },
      } : {
        requirement: check.value,
      }));
      edges.push(edge(id, goalId, "gates"));
      edges.push(edge(id, completionId, "verifies"));
      if (effect) {
        for (const [capabilityIndex, capability] of goal.capabilities.entries()) {
          if (isFamilyMatch(effect.family, capability.family) && !getCapabilityDenial(effect, [capability])) {
            edges.push(edge(`${goalId}:capability:${capabilityIndex}`, id, "authorizes"));
          }
        }
      }
    }

    for (const [index, invariant] of goal.invariants.entries()) {
      const id = `${goalId}:invariant:${index}`;
      nodes.push(node(id, "Invariant", invariant.value, invariant.span, {
        assertion: invariant.kind,
        invariant: invariant.value,
      }));
      edges.push(edge(id, goalId, "constrains"));
      edges.push(edge(id, completionId, "guards"));
      for (const targetId of guardTargetIds) {
        edges.push(edge(id, targetId, "guards"));
      }
    }
  }

  const graph = {
    schema_version: GRAPH_SCHEMA_VERSION,
    ast_schema_version: ast.schema_version,
    source: ast.source,
    package: ast.package?.name ?? "main",
    ok: diagnostics.length === 0,
    diagnostics,
    nodes,
    edges,
  };
  diagnostics.push(...validateGraph(graph, { allowNonExecutableEnvelope: diagnostics.length > 0 }));
  graph.ok = diagnostics.length === 0;
  return graph;
}

function validateGraph(graph, options = {}) {
  const diagnostics = [];
  const graphSpan = span(graphSourceFile(graph), 1, 1);
  if (graph.schema_version !== GRAPH_SCHEMA_VERSION || graph.ast_schema_version !== AST_SCHEMA_VERSION) {
    diagnostics.push(error("INTENT_GRAPH_SCHEMA_INVALID", `graph envelope uses unsupported schema version.`, graphSpan, {
      schema_version: graph.schema_version ?? null,
      expected_schema_version: GRAPH_SCHEMA_VERSION,
      ast_schema_version: graph.ast_schema_version ?? null,
      expected_ast_schema_version: AST_SCHEMA_VERSION,
    }));
  }
  if (
    typeof graph.source !== "string"
    || typeof graph.package !== "string"
    || graph.source.trim() === ""
    || graph.package.trim() === ""
  ) {
    diagnostics.push(error("INTENT_GRAPH_ENVELOPE_INVALID", `graph envelope must include non-empty string source and package fields.`, graphSpan, {
      source_is_string: typeof graph.source === "string",
      package_is_string: typeof graph.package === "string",
      source_is_nonempty: typeof graph.source === "string" && graph.source.trim() !== "",
      package_is_nonempty: typeof graph.package === "string" && graph.package.trim() !== "",
      source: typeof graph.source === "string" ? graph.source : null,
      package: typeof graph.package === "string" ? graph.package : null,
    }));
  }
  if (!options.allowNonExecutableEnvelope && (graph.ok !== true || !Array.isArray(graph.diagnostics) || graph.diagnostics.length !== 0)) {
    diagnostics.push(error("INTENT_GRAPH_EXECUTABLE_INVALID", `graph envelope must have ok true and an empty diagnostics array.`, graphSpan, {
      graph_ok: graph.ok ?? null,
      diagnostics_is_array: Array.isArray(graph.diagnostics),
      diagnostic_count: Array.isArray(graph.diagnostics) ? graph.diagnostics.length : null,
    }));
  }
  if (!Array.isArray(graph.diagnostics)) {
    diagnostics.push(error("INTENT_GRAPH_DIAGNOSTIC_INVALID", `graph diagnostics must be an array of error diagnostic records.`, graphSpan, {
      diagnostics_is_array: false,
      diagnostic_index: null,
      severity_is_error: null,
      code_is_nonempty: null,
      message_is_nonempty: null,
      span_is_valid: null,
    }));
  } else {
    for (const [diagnosticIndex, diagnostic] of graph.diagnostics.entries()) {
      if (!isDiagnosticRecord(diagnostic)) {
        diagnostics.push(error("INTENT_GRAPH_DIAGNOSTIC_INVALID", `graph diagnostics must be an array of error diagnostic records.`, isSpan(diagnostic?.span) ? diagnostic.span : graphSpan, {
          diagnostics_is_array: true,
          diagnostic_index: diagnosticIndex,
          severity_is_error: isPlainObject(diagnostic) && diagnostic.severity === "error",
          code_is_nonempty: isPlainObject(diagnostic) && typeof diagnostic.code === "string" && diagnostic.code.trim() !== "",
          message_is_nonempty: isPlainObject(diagnostic) && typeof diagnostic.message === "string" && diagnostic.message.trim() !== "",
          span_is_valid: isPlainObject(diagnostic) && isSpan(diagnostic.span),
        }));
      }
    }
  }
  if (!Array.isArray(graph.nodes) || !Array.isArray(graph.edges)) {
    diagnostics.push(error("INTENT_GRAPH_SHAPE_INVALID", `graph envelope must include nodes and edges arrays.`, graphSpan, {
      nodes_is_array: Array.isArray(graph.nodes),
      edges_is_array: Array.isArray(graph.edges),
    }));
    return diagnostics;
  }
  const nodesById = new Map();
  for (const [nodeIndex, graphNode] of graph.nodes.entries()) {
    if (
      !isPlainObject(graphNode)
      || typeof graphNode.id !== "string"
      || typeof graphNode.kind !== "string"
      || typeof graphNode.label !== "string"
      || graphNode.id.trim() === ""
      || graphNode.kind.trim() === ""
      || graphNode.label.trim() === ""
      || !isSpan(graphNode.span)
      || !isPlainObject(graphNode.data)
    ) {
      diagnostics.push(error("INTENT_GRAPH_NODE_INVALID", `graph node must be an object with string id, kind, label, span, and data fields.`, graphNode?.span ?? graphSpan, {
        node_index: nodeIndex,
        node_id: isPlainObject(graphNode) ? graphNode.id ?? null : null,
        node_kind: isPlainObject(graphNode) ? graphNode.kind ?? null : null,
        label_is_string: isPlainObject(graphNode) && typeof graphNode.label === "string",
        id_is_nonempty: isPlainObject(graphNode) && typeof graphNode.id === "string" && graphNode.id.trim() !== "",
        kind_is_nonempty: isPlainObject(graphNode) && typeof graphNode.kind === "string" && graphNode.kind.trim() !== "",
        label_is_nonempty: isPlainObject(graphNode) && typeof graphNode.label === "string" && graphNode.label.trim() !== "",
        span_is_valid: isPlainObject(graphNode) && isSpan(graphNode.span),
        data_is_object: isPlainObject(graphNode) && isPlainObject(graphNode.data),
      }));
      continue;
    }
    const previousNode = nodesById.get(graphNode.id);
    if (previousNode) {
      diagnostics.push(error("INTENT_GRAPH_NODE_DUPLICATE", `graph node id '${graphNode.id}' is emitted more than once.`, graphNode.span ?? previousNode.span ?? graphSpan, {
        node_id: graphNode.id,
        node_kind: graphNode.kind,
        previous_node_kind: previousNode.kind,
        previous_span: previousNode.span,
      }));
      continue;
    }
    if (!GRAPH_NODE_KINDS.has(graphNode.kind)) {
      diagnostics.push(error("INTENT_GRAPH_NODE_KIND_INVALID", `graph node kind '${graphNode.kind}' is not supported.`, graphNode.span ?? graphSpan, {
        node_id: graphNode.id,
        node_kind: graphNode.kind,
        supported_node_kinds: [...GRAPH_NODE_KINDS],
      }));
      continue;
    }
    const typeDiagnostic = validateGraphType(graphNode, graphSpan);
    if (typeDiagnostic) {
      diagnostics.push(typeDiagnostic);
    }
    const goalDiagnostic = validateGraphGoal(graphNode, graphSpan);
    if (goalDiagnostic) {
      diagnostics.push(goalDiagnostic);
    }
    const completionDiagnostic = validateGraphCompletion(graphNode, graphSpan);
    if (completionDiagnostic) {
      diagnostics.push(completionDiagnostic);
    }
    const invariantDiagnostic = validateGraphInvariant(graphNode, graphSpan);
    if (invariantDiagnostic) {
      diagnostics.push(invariantDiagnostic);
    }
    const capabilityDiagnostic = validateGraphCapability(graphNode, graphSpan);
    if (capabilityDiagnostic) {
      diagnostics.push(capabilityDiagnostic);
    }
    const memoryDiagnostic = validateGraphMemory(graphNode, graphSpan);
    if (memoryDiagnostic) {
      diagnostics.push(memoryDiagnostic);
    }
    const inputDiagnostic = validateGraphInput(graphNode, graphSpan);
    if (inputDiagnostic) {
      diagnostics.push(inputDiagnostic);
    }
    const stepDiagnostic = validateGraphStep(graphNode, graphSpan);
    if (stepDiagnostic) {
      diagnostics.push(stepDiagnostic);
    }
    const policyDiagnostic = validateGraphPolicy(graphNode, graphSpan);
    if (policyDiagnostic) {
      diagnostics.push(policyDiagnostic);
    }
    const approvalDiagnostic = validateGraphApproval(graphNode, graphSpan);
    if (approvalDiagnostic) {
      diagnostics.push(approvalDiagnostic);
    }
    const checkpointDiagnostic = validateGraphCheckpoint(graphNode, graphSpan);
    if (checkpointDiagnostic) {
      diagnostics.push(checkpointDiagnostic);
    }
    const effectDiagnostic = validateGraphEffect(graphNode, graphSpan);
    if (effectDiagnostic) {
      diagnostics.push(effectDiagnostic);
    }
    const contextDiagnostic = validateGraphContext(graphNode, graphSpan);
    if (contextDiagnostic) {
      diagnostics.push(contextDiagnostic);
    }
    const checkDiagnostic = validateGraphCheck(graphNode, graphSpan);
    if (checkDiagnostic) {
      diagnostics.push(checkDiagnostic);
    }
    const trustDiagnostic = validateGraphNodeTrust(graphNode, graphSpan);
    if (trustDiagnostic) {
      diagnostics.push(trustDiagnostic);
    }
    nodesById.set(graphNode.id, graphNode);
  }
  const fallbackSpan = graph.nodes[0]?.span ?? graphSpan;
  const outgoing = new Map([...nodesById.keys()].map((nodeId) => [nodeId, []]));
  const incomingEdgesByNode = new Map([...nodesById.keys()].map((nodeId) => [nodeId, []]));
  const outgoingEdgesByNode = new Map([...nodesById.keys()].map((nodeId) => [nodeId, []]));
  const incomingDataCounts = new Map();
  const incomingCompletionEdges = new Map();
  const incomingAuthorizationEdges = new Map();
  const guardTargetsByInvariant = new Map();

  for (const [edgeIndex, graphEdge] of graph.edges.entries()) {
    if (
      !isPlainObject(graphEdge)
      || typeof graphEdge.from !== "string"
      || typeof graphEdge.to !== "string"
      || typeof graphEdge.kind !== "string"
      || graphEdge.from.trim() === ""
      || graphEdge.to.trim() === ""
      || graphEdge.kind.trim() === ""
    ) {
      diagnostics.push(error("INTENT_GRAPH_EDGE_INVALID", `graph edge must be an object with string from, to, and kind fields.`, edgeDiagnosticSpan(nodesById, graphEdge, fallbackSpan), {
        edge_index: edgeIndex,
        edge: isPlainObject(graphEdge) ? graphEdge.kind ?? null : null,
        from: isPlainObject(graphEdge) ? graphEdge.from ?? null : null,
        to: isPlainObject(graphEdge) ? graphEdge.to ?? null : null,
        from_is_nonempty: isPlainObject(graphEdge) && typeof graphEdge.from === "string" && graphEdge.from.trim() !== "",
        to_is_nonempty: isPlainObject(graphEdge) && typeof graphEdge.to === "string" && graphEdge.to.trim() !== "",
        kind_is_nonempty: isPlainObject(graphEdge) && typeof graphEdge.kind === "string" && graphEdge.kind.trim() !== "",
      }));
      continue;
    }
    const dataIsPresent = graphEdge.data !== undefined;
    const dataIsObject = !dataIsPresent || isPlainObject(graphEdge.data);
    const sourceSpanIsValid = !dataIsPresent || graphEdge.data.sourceSpan === undefined || isSpan(graphEdge.data.sourceSpan);
    const targetSpanIsValid = !dataIsPresent || graphEdge.data.targetSpan === undefined || isSpan(graphEdge.data.targetSpan);
    if (!dataIsObject || !sourceSpanIsValid || !targetSpanIsValid) {
      diagnostics.push(error("INTENT_GRAPH_EDGE_PAYLOAD_INVALID", `graph edge data must be an object with valid sourceSpan and targetSpan values when present.`, edgeDiagnosticSpan(nodesById, graphEdge, fallbackSpan), {
        edge_index: edgeIndex,
        edge: graphEdge.kind,
        from: graphEdge.from,
        to: graphEdge.to,
        data_is_object: dataIsObject,
        source_span_is_valid: sourceSpanIsValid,
        target_span_is_valid: targetSpanIsValid,
      }));
      continue;
    }
    const missing = ["from", "to"].filter((endpoint) => !nodesById.has(graphEdge[endpoint]));
    if (missing.length > 0) {
      diagnostics.push(error("INTENT_GRAPH_EDGE_UNRESOLVED", `graph edge '${graphEdge.kind}' references missing endpoint '${missing.map((endpoint) => graphEdge[endpoint]).join(", ")}'.`, edgeDiagnosticSpan(nodesById, graphEdge, fallbackSpan), {
        edge: graphEdge.kind,
        from: graphEdge.from,
        to: graphEdge.to,
        missing_endpoints: missing,
      }));
      continue;
    }
    if (!GRAPH_EDGE_KINDS.has(graphEdge.kind)) {
      diagnostics.push(error("INTENT_GRAPH_EDGE_KIND_INVALID", `graph edge kind '${graphEdge.kind}' is not supported.`, edgeDiagnosticSpan(nodesById, graphEdge, fallbackSpan), {
        edge: graphEdge.kind,
        from: graphEdge.from,
        to: graphEdge.to,
        supported_edge_kinds: [...GRAPH_EDGE_KINDS],
      }));
      continue;
    }
    const semanticPayloadDiagnostic = validateGraphSemanticEdgePayload(nodesById, graphEdge, fallbackSpan);
    if (semanticPayloadDiagnostic) {
      diagnostics.push(semanticPayloadDiagnostic);
      continue;
    }
    const edgeRoleDiagnostic = validateGraphEdgeRole(nodesById, graphEdge, fallbackSpan);
    if (edgeRoleDiagnostic) {
      diagnostics.push(edgeRoleDiagnostic);
      continue;
    }
    outgoing.get(graphEdge.from).push(graphEdge.to);
    outgoingEdgesByNode.get(graphEdge.from).push(graphEdge);
    incomingEdgesByNode.get(graphEdge.to).push(graphEdge);
    if (nodesById.get(graphEdge.to)?.kind === "Completion") {
      const completionEdges = incomingCompletionEdges.get(graphEdge.to) ?? [];
      completionEdges.push(graphEdge);
      incomingCompletionEdges.set(graphEdge.to, completionEdges);
    }
    if (graphEdge.kind === "authorizes") {
      const authorizationEdges = incomingAuthorizationEdges.get(graphEdge.to) ?? [];
      authorizationEdges.push(graphEdge);
      incomingAuthorizationEdges.set(graphEdge.to, authorizationEdges);
    }
    if (graphEdge.kind === "guards" && nodesById.get(graphEdge.from)?.kind === "Invariant") {
      const guardTargets = guardTargetsByInvariant.get(graphEdge.from) ?? new Set();
      guardTargets.add(graphEdge.to);
      guardTargetsByInvariant.set(graphEdge.from, guardTargets);
    }
    if (graphEdge.kind === "data") {
      const sourceNode = nodesById.get(graphEdge.from);
      const targetNode = nodesById.get(graphEdge.to);
      const sourceIsProducer = (sourceNode.kind === "Input" && sourceNode.data?.scope === "goal") || sourceNode.kind === "Step";
      const targetIsStepInput = targetNode.kind === "Input" && targetNode.data?.scope === "step";
      if (!sourceIsProducer || !targetIsStepInput) {
        diagnostics.push(error("INTENT_GRAPH_DATA_INVALID", `graph data edge must connect a goal input or step producer to a step input.`, edgeDiagnosticSpan(nodesById, graphEdge, fallbackSpan), {
          edge: graphEdge.kind,
          from: graphEdge.from,
          to: graphEdge.to,
          from_kind: sourceNode.kind,
          to_kind: targetNode.kind,
        }));
        continue;
      }
      incomingDataCounts.set(graphEdge.to, (incomingDataCounts.get(graphEdge.to) ?? 0) + 1);
    }
  }

  for (const graphNode of graph.nodes) {
    const attachment = stepAttachment(graphNode);
    if (!attachment) {
      continue;
    }
    const missingEdges = [];
    const missingApprovalTargets = [];
    const ownerStep = attachment.ownerStepId ? nodesById.get(attachment.ownerStepId) : null;

    if (!ownerStep || ownerStep.kind !== "Step") {
      missingEdges.push({
        kind: attachment.edgeKind,
        from: attachment.direction === "incoming" ? attachment.ownerStepId : graphNode.id,
        to: attachment.direction === "incoming" ? graphNode.id : attachment.ownerStepId,
      });
    } else if (attachment.direction === "incoming") {
      const incomingEdges = incomingEdgesByNode.get(graphNode.id) ?? [];
      const matchingEdges = incomingEdges.filter((graphEdge) => {
        return graphEdge.kind === attachment.edgeKind && graphEdge.from === attachment.ownerStepId;
      });
      if (matchingEdges.length !== 1) {
        missingEdges.push({ kind: attachment.edgeKind, from: attachment.ownerStepId, to: graphNode.id });
      }
    } else {
      const outgoingEdges = outgoingEdgesByNode.get(graphNode.id) ?? [];
      const matchingEdges = outgoingEdges.filter((graphEdge) => {
        return graphEdge.kind === attachment.edgeKind && graphEdge.to === attachment.ownerStepId;
      });
      if (matchingEdges.length !== 1) {
        missingEdges.push({ kind: attachment.edgeKind, from: graphNode.id, to: attachment.ownerStepId });
      }
    }

    if (graphNode.kind === "Approval" && attachment.ownerStepId) {
      const outgoingEdges = outgoingEdgesByNode.get(graphNode.id) ?? [];
      const approvalRequiredEffectIds = graph.nodes
        .filter((candidate) => {
          return candidate.kind === "Effect"
            && candidate.data?.approvalRequired === true
            && candidate.id.startsWith(`${attachment.ownerStepId}:effect:`);
        })
        .map((candidate) => candidate.id);
      for (const effectId of approvalRequiredEffectIds) {
        const hasApprovalEdge = outgoingEdges.some((graphEdge) => graphEdge.kind === "approves" && graphEdge.to === effectId);
        if (!hasApprovalEdge) {
          missingApprovalTargets.push(effectId);
        }
      }
    }

    if (missingEdges.length > 0 || missingApprovalTargets.length > 0) {
      diagnostics.push(error("INTENT_GRAPH_STEP_ATTACHMENT_INVALID", `${graphNode.kind} '${graphNode.label}' must be attached to its owning step with graph edges.`, graphNode.span ?? fallbackSpan, {
        node: graphNode.label,
        node_id: graphNode.id,
        node_kind: graphNode.kind,
        owner_step_id: attachment.ownerStepId,
        missing_edges: missingEdges,
        missing_approval_targets: missingApprovalTargets,
      }));
    }
  }

  for (const graphNode of graph.nodes) {
    if (graphNode.kind !== "Effect") {
      continue;
    }
    const ownerStepId = parentNodeId(graphNode.id, ":effect:");
    const ownerStep = ownerStepId ? nodesById.get(ownerStepId) : null;
    const requestEdges = (incomingEdgesByNode.get(graphNode.id) ?? []).filter((graphEdge) => graphEdge.kind === "requests");
    const ownerStepRequestEdges = requestEdges.filter((graphEdge) => graphEdge.from === ownerStepId && ownerStep?.kind === "Step");
    if (ownerStepRequestEdges.length !== 1 || requestEdges.length !== ownerStepRequestEdges.length) {
      diagnostics.push(error("INTENT_GRAPH_EFFECT_REQUEST_INVALID", `effect '${graphNode.label}' must have exactly one incoming requests edge from its owning step.`, graphNode.span ?? fallbackSpan, {
        effect: graphNode.label,
        effect_id: graphNode.id,
        owner_step_id: ownerStepId,
        request_edges: requestEdges.length,
        owner_step_request_edges: ownerStepRequestEdges.length,
      }));
    }
  }

  for (const graphNode of graph.nodes) {
    if (!requiresCapabilityAuthorization(graphNode)) {
      continue;
    }
    const authorizationEdges = incomingAuthorizationEdges.get(graphNode.id) ?? [];
    const capabilityAuthorizationEdges = authorizationEdges.filter((graphEdge) => nodesById.get(graphEdge.from)?.kind === "Capability");
    if (authorizationEdges.length === 0 || authorizationEdges.length !== capabilityAuthorizationEdges.length) {
      diagnostics.push(error("INTENT_GRAPH_AUTHORIZATION_INVALID", `${graphNode.kind} '${graphNode.label}' must have incoming authorizes edges from Capability nodes.`, graphNode.span ?? fallbackSpan, {
        target: graphNode.label,
        target_id: graphNode.id,
        target_kind: graphNode.kind,
        authorizes_edges: authorizationEdges.length,
        capability_authorizes_edges: capabilityAuthorizationEdges.length,
      }));
    }
  }

  for (const graphNode of graph.nodes) {
    if (graphNode.kind !== "Capability") {
      continue;
    }
    const ownershipDiagnostic = validateGraphCapabilityAuthorization(nodesById, outgoingEdgesByNode, graphNode, fallbackSpan);
    if (ownershipDiagnostic) {
      diagnostics.push(ownershipDiagnostic);
    }
  }

  for (const graphNode of graph.nodes) {
    if (graphNode.kind !== "Context") {
      continue;
    }
    const informsDiagnostic = validateGraphContextInforms(nodesById, outgoingEdgesByNode, graphNode, fallbackSpan);
    if (informsDiagnostic) {
      diagnostics.push(informsDiagnostic);
    }
  }

  for (const graphNode of graph.nodes) {
    if (graphNode.kind !== "Memory") {
      continue;
    }
    const declareDiagnostic = validateGraphMemoryDeclare(nodesById, incomingEdgesByNode, graphNode, fallbackSpan);
    if (declareDiagnostic) {
      diagnostics.push(declareDiagnostic);
    }
  }

  for (const graphNode of graph.nodes) {
    if (graphNode.kind !== "Type") {
      continue;
    }
    const declareDiagnostic = validateGraphTypeDeclarations(nodesById, outgoingEdgesByNode, graphNode, fallbackSpan);
    if (declareDiagnostic) {
      diagnostics.push(declareDiagnostic);
    }
  }

  for (const graphNode of graph.nodes) {
    if (graphNode.kind !== "Completion") {
      continue;
    }
    const incomingEdges = incomingCompletionEdges.get(graphNode.id) ?? [];
    const completingEdges = incomingEdges.filter((graphEdge) => graphEdge.kind === "completes" && nodesById.get(graphEdge.from)?.kind === "Goal");
    const producingEdges = incomingEdges.filter((graphEdge) => graphEdge.kind === "produces" && nodesById.get(graphEdge.from)?.kind === "Step");
    const verifyingEdges = incomingEdges.filter((graphEdge) => graphEdge.kind === "verifies" && nodesById.get(graphEdge.from)?.kind === "Check");
    const guardingEdges = incomingEdges.filter((graphEdge) => graphEdge.kind === "guards" && nodesById.get(graphEdge.from)?.kind === "Invariant");
    const goalId = graphNode.id.endsWith(":completion") ? graphNode.id.slice(0, -":completion".length) : null;
    const expectedGuardEdges = goalId
      ? graph.nodes.filter((candidate) => candidate.kind === "Invariant" && candidate.id.startsWith(`${goalId}:invariant:`)).length
      : guardingEdges.length;
    if (completingEdges.length !== 1 || producingEdges.length !== 1 || verifyingEdges.length < 1 || guardingEdges.length !== expectedGuardEdges) {
      diagnostics.push(error("INTENT_GRAPH_COMPLETION_INVALID", `completion '${graphNode.label}' must have incoming completes, produces, verifies, and invariant guard edges.`, graphNode.span ?? fallbackSpan, {
        completion: graphNode.label,
        completion_id: graphNode.id,
        completes_edges: completingEdges.length,
        produces_edges: producingEdges.length,
        verifies_edges: verifyingEdges.length,
        guards_edges: guardingEdges.length,
        expected_guard_edges: expectedGuardEdges,
      }));
    }
  }

  for (const graphNode of graph.nodes) {
    if (graphNode.kind !== "Check") {
      continue;
    }
    const gateDiagnostic = validateGraphCheckGate(nodesById, outgoingEdgesByNode, graphNode, fallbackSpan);
    if (gateDiagnostic) {
      diagnostics.push(gateDiagnostic);
    }
  }

  for (const graphNode of graph.nodes) {
    if (graphNode.kind !== "Invariant") {
      continue;
    }
    const constraintDiagnostic = validateGraphInvariantConstraint(nodesById, outgoingEdgesByNode, graphNode, fallbackSpan);
    if (constraintDiagnostic) {
      diagnostics.push(constraintDiagnostic);
    }
    const goalId = invariantGoalId(graphNode.id);
    if (!goalId) {
      continue;
    }
    const guardedTargets = guardTargetsByInvariant.get(graphNode.id) ?? new Set();
    const missingGuardTargets = invariantGuardTargetIds(graph.nodes, goalId).filter((targetId) => !guardedTargets.has(targetId));
    if (missingGuardTargets.length > 0) {
      diagnostics.push(error("INTENT_GRAPH_GUARD_INVALID", `invariant '${graphNode.label}' must guard completion and step-scoped effect, checkpoint, and requirement nodes.`, graphNode.span ?? fallbackSpan, {
        invariant: graphNode.label,
        invariant_id: graphNode.id,
        missing_guard_targets: missingGuardTargets,
      }));
    }
  }

  for (const graphNode of graph.nodes) {
    if (graphNode.kind !== "Input" || graphNode.data?.scope !== "step") {
      continue;
    }
    const incomingDataCount = incomingDataCounts.get(graphNode.id) ?? 0;
    if (incomingDataCount !== 1) {
      diagnostics.push(error("INTENT_GRAPH_INPUT_UNBOUND", `step input '${graphNode.label}' must have exactly one incoming data edge.`, graphNode.span ?? fallbackSpan, {
        input: graphNode.label,
        input_id: graphNode.id,
        incoming_data_edges: incomingDataCount,
      }));
    }
  }

  for (const graphNode of graph.nodes) {
    if (graphNode.kind !== "Input" || graphNode.data?.scope !== "goal") {
      continue;
    }
    const supplyDiagnostic = validateGraphInputSupply(nodesById, outgoingEdgesByNode, graphNode, fallbackSpan);
    if (supplyDiagnostic) {
      diagnostics.push(supplyDiagnostic);
    }
  }

  for (const graphNode of graph.nodes) {
    if (graphNode.kind !== "Step") {
      continue;
    }
    const ownerGoalId = parentNodeId(graphNode.id, ":step:");
    const ownerGoal = ownerGoalId ? nodesById.get(ownerGoalId) : null;
    const planEdges = (incomingEdgesByNode.get(graphNode.id) ?? []).filter((graphEdge) => graphEdge.kind === "plans");
    const ownerPlanEdges = planEdges.filter((graphEdge) => graphEdge.from === ownerGoalId && ownerGoal?.kind === "Goal");
    if (ownerPlanEdges.length !== 1 || planEdges.length !== ownerPlanEdges.length) {
      diagnostics.push(error("INTENT_GRAPH_STEP_PLAN_INVALID", `step '${graphNode.label}' must have exactly one incoming plans edge from its owning goal.`, graphNode.span ?? fallbackSpan, {
        step: graphNode.label,
        step_id: graphNode.id,
        owner_goal_id: ownerGoalId,
        plans_edges: planEdges.length,
        owner_goal_plans_edges: ownerPlanEdges.length,
      }));
    }
  }

  for (const graphNode of graph.nodes) {
    if (graphNode.kind !== "Goal") {
      continue;
    }
    const sequenceDiagnostic = validateGoalStepSequence(graph, nodesById, incomingEdgesByNode, graphNode, fallbackSpan);
    if (sequenceDiagnostic) {
      diagnostics.push(sequenceDiagnostic);
    }
  }

  for (const graphNode of graph.nodes) {
    if (graphNode.kind !== "Goal") {
      continue;
    }
    const completionDiagnostic = validateGoalCompletionOwnership(nodesById, outgoingEdgesByNode, graphNode, fallbackSpan);
    if (completionDiagnostic) {
      diagnostics.push(completionDiagnostic);
    }
  }

  const visiting = new Set();
  const visited = new Set();
  let cycleReported = false;
  const visit = (nodeId, stack) => {
    if (cycleReported) {
      return;
    }
    if (visiting.has(nodeId)) {
      const cycle = [...stack, nodeId];
      diagnostics.push(error("INTENT_GRAPH_CYCLE", `graph contains execution cycle '${cycle.join(" -> ")}'.`, nodesById.get(nodeId)?.span ?? fallbackSpan, {
        cycle,
      }));
      cycleReported = true;
      return;
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

  for (const nodeId of nodesById.keys()) {
    visit(nodeId, []);
  }

  return diagnostics;
}

function isDiagnosticRecord(value) {
  return isPlainObject(value)
    && value.severity === "error"
    && typeof value.code === "string"
    && value.code.trim() !== ""
    && typeof value.message === "string"
    && value.message.trim() !== ""
    && isSpan(value.span);
}

function validateGraphType(graphNode, graphSpan) {
  if (graphNode.kind !== "Type") {
    return null;
  }
  const definitionIsValid = graphNode.data.definition === null
    || (typeof graphNode.data.definition === "string" && graphNode.data.definition.trim() !== "");
  if (definitionIsValid) {
    return null;
  }
  return error("INTENT_GRAPH_TYPE_INVALID", `type '${graphNode.label}' must carry valid declaration data.`, graphNode.span ?? graphSpan, {
    type: graphNode.label,
    type_id: graphNode.id,
    definition_is_valid: definitionIsValid,
  });
}

function validateGraphTypeDeclarations(nodesById, outgoingEdgesByNode, graphNode, fallbackSpan) {
  const goalIds = [...nodesById.values()]
    .filter((candidate) => candidate.kind === "Goal")
    .map((candidate) => candidate.id);
  if (goalIds.length === 0) {
    return null;
  }
  const goalIdSet = new Set(goalIds);
  const declareEdges = (outgoingEdgesByNode.get(graphNode.id) ?? []).filter((graphEdge) => graphEdge.kind === "declares");
  const declaredGoalCounts = new Map();
  const invalidTargetIds = [];
  for (const graphEdge of declareEdges) {
    if (!goalIdSet.has(graphEdge.to)) {
      invalidTargetIds.push(graphEdge.to);
      continue;
    }
    declaredGoalCounts.set(graphEdge.to, (declaredGoalCounts.get(graphEdge.to) ?? 0) + 1);
  }
  const missingGoalIds = goalIds.filter((goalId) => !declaredGoalCounts.has(goalId));
  const duplicateGoalIds = goalIds.filter((goalId) => (declaredGoalCounts.get(goalId) ?? 0) > 1);
  if (missingGoalIds.length === 0 && duplicateGoalIds.length === 0 && invalidTargetIds.length === 0) {
    return null;
  }
  return error("INTENT_GRAPH_TYPE_DECLARE_INVALID", `type '${graphNode.label}' must declare availability to every goal exactly once.`, graphNode.span ?? fallbackSpan, {
    type: graphNode.label,
    type_id: graphNode.id,
    goal_count: goalIds.length,
    declares_edges: declareEdges.length,
    missing_goal_ids: missingGoalIds,
    duplicate_goal_ids: duplicateGoalIds,
    invalid_target_ids: invalidTargetIds,
  });
}

function validateGraphGoal(graphNode, graphSpan) {
  if (graphNode.kind !== "Goal") {
    return null;
  }
  const titleIsValid = graphNode.data.title === null
    || (typeof graphNode.data.title === "string" && graphNode.data.title.trim() !== "");
  const parametersIsArray = Array.isArray(graphNode.data.parameters);
  const invalidParameterIndexes = parametersIsArray
    ? graphNode.data.parameters
        .map((parameter, parameterIndex) => isGraphParameterRecord(parameter) ? null : parameterIndex)
        .filter((parameterIndex) => parameterIndex !== null)
    : [];
  const outputTypeIsValid = graphNode.data.outputType === null
    || (typeof graphNode.data.outputType === "string" && graphNode.data.outputType.trim() !== "");
  const outputTypeSpanIsValid = graphNode.data.outputTypeSpan === undefined
    || graphNode.data.outputTypeSpan === null
    || isSpan(graphNode.data.outputTypeSpan);
  if (titleIsValid && parametersIsArray && invalidParameterIndexes.length === 0 && outputTypeIsValid && outputTypeSpanIsValid) {
    return null;
  }
  return error("INTENT_GRAPH_GOAL_INVALID", `goal '${graphNode.label}' must carry valid typed contract data.`, graphNode.span ?? graphSpan, {
    goal: graphNode.label,
    goal_id: graphNode.id,
    title_is_valid: titleIsValid,
    parameters_is_array: parametersIsArray,
    invalid_parameter_indexes: invalidParameterIndexes,
    output_type_is_valid: outputTypeIsValid,
    output_type_span_is_valid: outputTypeSpanIsValid,
  });
}

function validateGraphCompletion(graphNode, graphSpan) {
  if (graphNode.kind !== "Completion") {
    return null;
  }
  const outputTypeIsValid = graphNode.data.outputType === null
    || (typeof graphNode.data.outputType === "string" && graphNode.data.outputType.trim() !== "");
  const outputTypeSpanIsValid = graphNode.data.outputTypeSpan === null || isSpan(graphNode.data.outputTypeSpan);
  if (outputTypeIsValid && outputTypeSpanIsValid) {
    return null;
  }
  return error("INTENT_GRAPH_COMPLETION_INVALID", `completion '${graphNode.label}' must carry valid output contract data.`, graphNode.span ?? graphSpan, {
    completion: graphNode.label,
    completion_id: graphNode.id,
    output_type_is_valid: outputTypeIsValid,
    output_type_span_is_valid: outputTypeSpanIsValid,
  });
}

function validateGraphInvariant(graphNode, graphSpan) {
  if (graphNode.kind !== "Invariant") {
    return null;
  }
  const assertionIsValid = graphNode.data.assertion === "Require" || graphNode.data.assertion === "Deny";
  const invariantIsNonempty = typeof graphNode.data.invariant === "string" && graphNode.data.invariant.trim() !== "";
  if (assertionIsValid && invariantIsNonempty) {
    return null;
  }
  return error("INTENT_GRAPH_INVARIANT_INVALID", `invariant '${graphNode.label}' must carry valid assertion data.`, graphNode.span ?? graphSpan, {
    invariant: graphNode.label,
    invariant_id: graphNode.id,
    assertion: typeof graphNode.data.assertion === "string" ? graphNode.data.assertion : null,
    assertion_is_valid: assertionIsValid,
    invariant_is_nonempty: invariantIsNonempty,
  });
}

function validateGraphCapability(graphNode, graphSpan) {
  if (graphNode.kind !== "Capability") {
    return null;
  }
  const familyIsNonempty = typeof graphNode.data.family === "string" && graphNode.data.family.trim() !== "";
  const grantsIsArray = Array.isArray(graphNode.data.grants);
  const approvalPolicyIsValid = graphNode.data.approvalPolicy === "none" || graphNode.data.approvalPolicy === "required";
  if (familyIsNonempty && grantsIsArray && approvalPolicyIsValid) {
    return null;
  }
  return error("INTENT_GRAPH_CAPABILITY_INVALID", `capability '${graphNode.label}' must carry valid authorization policy data.`, graphNode.span ?? graphSpan, {
    capability: graphNode.label,
    capability_id: graphNode.id,
    family: typeof graphNode.data.family === "string" ? graphNode.data.family : null,
    approval_policy: typeof graphNode.data.approvalPolicy === "string" ? graphNode.data.approvalPolicy : null,
    family_is_nonempty: familyIsNonempty,
    grants_is_array: grantsIsArray,
    approval_policy_is_valid: approvalPolicyIsValid,
  });
}

function validateGraphCapabilityAuthorization(nodesById, outgoingEdgesByNode, graphNode, fallbackSpan) {
  const ownerGoalId = parentNodeId(graphNode.id, ":capability:");
  const ownerGoal = ownerGoalId ? nodesById.get(ownerGoalId) : null;
  if (ownerGoal?.kind !== "Goal") {
    return null;
  }
  const authorizationEdges = (outgoingEdgesByNode.get(graphNode.id) ?? []).filter((graphEdge) => graphEdge.kind === "authorizes");
  const ownerGoalAuthorizationEdges = authorizationEdges.filter((graphEdge) => graphEdge.to === ownerGoalId);
  const wrongGoalAuthorizationEdges = authorizationEdges.filter((graphEdge) => {
    return graphEdge.to !== ownerGoalId && nodesById.get(graphEdge.to)?.kind === "Goal";
  });
  if (ownerGoalAuthorizationEdges.length === 1 && wrongGoalAuthorizationEdges.length === 0) {
    return null;
  }
  return error("INTENT_GRAPH_CAPABILITY_AUTHORIZES_INVALID", `capability '${graphNode.label}' must authorize its owning goal exactly once.`, graphNode.span ?? fallbackSpan, {
    capability: graphNode.label,
    capability_id: graphNode.id,
    owner_goal_id: ownerGoalId,
    authorizes_edges: authorizationEdges.length,
    owner_goal_authorizes_edges: ownerGoalAuthorizationEdges.length,
    wrong_goal_authorizes_edges: wrongGoalAuthorizationEdges.length,
  });
}

function validateGraphMemory(graphNode, graphSpan) {
  if (graphNode.kind !== "Memory") {
    return null;
  }
  const retentionIsArray = Array.isArray(graphNode.data.retention);
  const retentionRulesIsArray = Array.isArray(graphNode.data.retentionRules);
  const retentionRulesNonempty = retentionRulesIsArray && graphNode.data.retentionRules.length > 0;
  const invalidRetentionIndexes = retentionRulesIsArray
    ? graphNode.data.retentionRules
        .map((retentionRule, retentionIndex) => isGraphRetentionRuleRecord(retentionRule) ? null : retentionIndex)
        .filter((retentionIndex) => retentionIndex !== null)
    : [];
  if (retentionIsArray && retentionRulesNonempty && invalidRetentionIndexes.length === 0) {
    return null;
  }
  return error("INTENT_GRAPH_MEMORY_INVALID", `memory '${graphNode.label}' must carry valid retention lifecycle data.`, graphNode.span ?? graphSpan, {
    memory: graphNode.label,
    memory_id: graphNode.id,
    scope: typeof graphNode.data.scope === "string" ? graphNode.data.scope : null,
    retention_is_array: retentionIsArray,
    retention_rules_is_array: retentionRulesIsArray,
    retention_rules_nonempty: retentionRulesNonempty,
    invalid_retention_indexes: invalidRetentionIndexes,
  });
}

function isGraphRetentionRuleRecord(value) {
  return isPlainObject(value)
    && typeof value.raw === "string"
    && value.raw.trim() !== ""
    && isPlainObject(value.subject)
    && typeof value.subject.raw === "string"
    && value.subject.raw.trim() !== ""
    && isPlainObject(value.until)
    && typeof value.until.raw === "string"
    && value.until.raw.trim() !== ""
    && isSupportedRetentionUntil(value.until.raw);
}

function validateGraphMemoryDeclare(nodesById, incomingEdgesByNode, graphNode, fallbackSpan) {
  const ownerGoalId = parentNodeId(graphNode.id, ":memory:");
  const ownerGoal = ownerGoalId ? nodesById.get(ownerGoalId) : null;
  if (ownerGoal?.kind !== "Goal") {
    return null;
  }
  const declareEdges = (incomingEdgesByNode.get(graphNode.id) ?? []).filter((graphEdge) => graphEdge.kind === "declares");
  const ownerGoalDeclareEdges = declareEdges.filter((graphEdge) => graphEdge.from === ownerGoalId);
  const wrongGoalDeclareEdges = declareEdges.filter((graphEdge) => {
    return graphEdge.from !== ownerGoalId && nodesById.get(graphEdge.from)?.kind === "Goal";
  });
  if (ownerGoalDeclareEdges.length === 1 && declareEdges.length === ownerGoalDeclareEdges.length) {
    return null;
  }
  return error("INTENT_GRAPH_MEMORY_DECLARE_INVALID", `memory '${graphNode.label}' must be declared by its owning goal exactly once.`, graphNode.span ?? fallbackSpan, {
    memory: graphNode.label,
    memory_id: graphNode.id,
    owner_goal_id: ownerGoalId,
    declares_edges: declareEdges.length,
    owner_goal_declares_edges: ownerGoalDeclareEdges.length,
    wrong_goal_declares_edges: wrongGoalDeclareEdges.length,
  });
}

function validateGraphInput(graphNode, graphSpan) {
  if (graphNode.kind !== "Input") {
    return null;
  }
  const scopeIsValid = graphNode.data.scope === "goal" || graphNode.data.scope === "step";
  const typeIsNonempty = typeof graphNode.data.type === "string" && graphNode.data.type.trim() !== "";
  if (scopeIsValid && typeIsNonempty) {
    return null;
  }
  return error("INTENT_GRAPH_INPUT_INVALID", `input '${graphNode.label}' must carry valid typed binding data.`, graphNode.span ?? graphSpan, {
    input: graphNode.label,
    input_id: graphNode.id,
    scope: typeof graphNode.data.scope === "string" ? graphNode.data.scope : null,
    type: typeof graphNode.data.type === "string" ? graphNode.data.type : null,
    scope_is_valid: scopeIsValid,
    type_is_nonempty: typeIsNonempty,
  });
}

function validateGraphStep(graphNode, graphSpan) {
  if (graphNode.kind !== "Step") {
    return null;
  }
  const inputsIsArray = Array.isArray(graphNode.data.inputs);
  const invalidInputIndexes = inputsIsArray
    ? graphNode.data.inputs
        .map((input, inputIndex) => isGraphParameterRecord(input) ? null : inputIndex)
        .filter((inputIndex) => inputIndex !== null)
    : [];
  const outputTypeIsValid = graphNode.data.outputType === null
    || (typeof graphNode.data.outputType === "string" && graphNode.data.outputType.trim() !== "");
  const outputTypeSpanIsValid = graphNode.data.outputTypeSpan === undefined
    || graphNode.data.outputTypeSpan === null
    || isSpan(graphNode.data.outputTypeSpan);
  const effectsAreValid = isNonemptyStringArray(graphNode.data.effects);
  const requirementsAreValid = isNonemptyStringArray(graphNode.data.requirements);
  const checkpointsAreValid = isNonemptyStringArray(graphNode.data.checkpoints);
  const approvalsAreValid = isNonemptyStringArray(graphNode.data.approvals);
  const timeoutsAreValid = isNonemptyStringArray(graphNode.data.timeouts);
  const retriesAreValid = isNonemptyStringArray(graphNode.data.retries);
  if (
    inputsIsArray
    && invalidInputIndexes.length === 0
    && outputTypeIsValid
    && outputTypeSpanIsValid
    && effectsAreValid
    && requirementsAreValid
    && checkpointsAreValid
    && approvalsAreValid
    && timeoutsAreValid
    && retriesAreValid
  ) {
    return null;
  }
  return error("INTENT_GRAPH_STEP_INVALID", `step '${graphNode.label}' must carry valid plan payload data.`, graphNode.span ?? graphSpan, {
    step: graphNode.label,
    step_id: graphNode.id,
    inputs_is_array: inputsIsArray,
    invalid_input_indexes: invalidInputIndexes,
    output_type_is_valid: outputTypeIsValid,
    output_type_span_is_valid: outputTypeSpanIsValid,
    effects_are_valid: effectsAreValid,
    requirements_are_valid: requirementsAreValid,
    checkpoints_are_valid: checkpointsAreValid,
    approvals_are_valid: approvalsAreValid,
    timeouts_are_valid: timeoutsAreValid,
    retries_are_valid: retriesAreValid,
  });
}

function isGraphParameterRecord(value) {
  return isPlainObject(value)
    && typeof value.name === "string"
    && value.name.trim() !== ""
    && typeof value.type === "string"
    && value.type.trim() !== ""
    && isSpan(value.span);
}

function isNonemptyStringArray(value) {
  return Array.isArray(value) && value.every((item) => typeof item === "string" && item.trim() !== "");
}

function validateGraphSemanticEdgePayload(nodesById, graphEdge, fallbackSpan) {
  if (![
    "data",
    "produces",
    "requires",
    "approves",
    "timeouts",
    "retries",
    "checkpoints",
  ].includes(graphEdge.kind)) {
    return null;
  }
  const payload = isPlainObject(graphEdge.data) ? graphEdge.data : {};
  const sourceNode = nodesById.get(graphEdge.from);
  const targetNode = nodesById.get(graphEdge.to);
  const parameterIsNonempty = typeof payload.parameter === "string" && payload.parameter.trim() !== "";
  const typeIsNonempty = typeof payload.type === "string" && payload.type.trim() !== "";
  const requirementIsNonempty = typeof payload.requirement === "string" && payload.requirement.trim() !== "";
  const approvalIsNonempty = typeof payload.approval === "string" && payload.approval.trim() !== "";
  const policyIsNonempty = typeof payload.policy === "string" && payload.policy.trim() !== "";
  const checkpointIsNonempty = typeof payload.checkpoint === "string" && payload.checkpoint.trim() !== "";
  const sourceSpanIsValid = isSpan(payload.sourceSpan);
  const targetSpanIsValid = isSpan(payload.targetSpan);
  const requiresStepInput = graphEdge.kind === "requires" && sourceNode?.kind === "Input" && targetNode?.kind === "Step";
  const requiresStepRequirement = graphEdge.kind === "requires"
    && sourceNode?.kind === "Check"
    && sourceNode.data?.scope === "step"
    && targetNode?.kind === "Step";
  const approvesStepOrEffect = graphEdge.kind === "approves"
    && sourceNode?.kind === "Approval"
    && (targetNode?.kind === "Step" || targetNode?.kind === "Effect");
  const policyAttachesToStep = (graphEdge.kind === "timeouts" || graphEdge.kind === "retries")
    && sourceNode?.kind === "Policy"
    && targetNode?.kind === "Step";
  const stepCheckpoints = graphEdge.kind === "checkpoints"
    && sourceNode?.kind === "Step"
    && targetNode?.kind === "Checkpoint";
  const payloadIsValid = graphEdge.kind === "data"
    ? parameterIsNonempty && typeIsNonempty && sourceSpanIsValid && targetSpanIsValid
    : graphEdge.kind === "produces"
      ? typeIsNonempty && sourceSpanIsValid && targetSpanIsValid
      : requiresStepInput
        ? parameterIsNonempty && typeIsNonempty && targetSpanIsValid
        : requiresStepRequirement
          ? requirementIsNonempty
          : approvesStepOrEffect
            ? approvalIsNonempty
            : policyAttachesToStep
              ? policyIsNonempty
              : !stepCheckpoints || checkpointIsNonempty;
  if (payloadIsValid) {
    return null;
  }
  return error("INTENT_GRAPH_EDGE_PAYLOAD_INVALID", `${graphEdge.kind} edge '${graphEdge.from}' to '${graphEdge.to}' must carry valid typed binding data.`, edgeDiagnosticSpan(nodesById, graphEdge, fallbackSpan), {
    edge: graphEdge.kind,
    from: graphEdge.from,
    to: graphEdge.to,
    parameter: typeof payload.parameter === "string" ? payload.parameter : null,
    type: typeof payload.type === "string" ? payload.type : null,
    requirement: typeof payload.requirement === "string" ? payload.requirement : null,
    approval: typeof payload.approval === "string" ? payload.approval : null,
    policy: typeof payload.policy === "string" ? payload.policy : null,
    checkpoint: typeof payload.checkpoint === "string" ? payload.checkpoint : null,
    parameter_is_nonempty: parameterIsNonempty,
    type_is_nonempty: typeIsNonempty,
    requirement_is_nonempty: requirementIsNonempty,
    approval_is_nonempty: approvalIsNonempty,
    policy_is_nonempty: policyIsNonempty,
    checkpoint_is_nonempty: checkpointIsNonempty,
    source_span_is_valid: sourceSpanIsValid,
    target_span_is_valid: targetSpanIsValid,
  });
}

function validateGraphEdgeRole(nodesById, graphEdge, fallbackSpan) {
  if (!["declares", "authorizes", "requests", "gates", "verifies", "plans", "completes", "produces"].includes(graphEdge.kind)) {
    return null;
  }
  const sourceNode = nodesById.get(graphEdge.from);
  const targetNode = nodesById.get(graphEdge.to);
  if (graphEdge.kind === "completes") {
    return validateGraphCompletesEdgeRole(nodesById, graphEdge, sourceNode, targetNode, fallbackSpan);
  }
  if (graphEdge.kind === "produces") {
    return validateGraphProducesEdgeRole(nodesById, graphEdge, sourceNode, targetNode, fallbackSpan);
  }
  if (graphEdge.kind === "authorizes") {
    return validateGraphAuthorizesEdgeRole(nodesById, graphEdge, sourceNode, targetNode, fallbackSpan);
  }
  if (graphEdge.kind === "requests") {
    return validateGraphRequestsEdgeRole(nodesById, graphEdge, sourceNode, targetNode, fallbackSpan);
  }
  if (graphEdge.kind === "gates") {
    return validateGraphGatesEdgeRole(nodesById, graphEdge, sourceNode, targetNode, fallbackSpan);
  }
  if (graphEdge.kind === "verifies") {
    return validateGraphVerifiesEdgeRole(nodesById, graphEdge, sourceNode, targetNode, fallbackSpan);
  }
  if (graphEdge.kind === "plans") {
    return validateGraphPlansEdgeRole(nodesById, graphEdge, sourceNode, targetNode, fallbackSpan);
  }
  const isTypeAvailability = sourceNode?.kind === "Type" && targetNode?.kind === "Goal";
  const isMemoryOwnership = sourceNode?.kind === "Goal" && targetNode?.kind === "Memory";
  if (isTypeAvailability || isMemoryOwnership) {
    return null;
  }
  return error("INTENT_GRAPH_DECLARE_INVALID", `declares edge '${graphEdge.from}' to '${graphEdge.to}' must connect a supported declaration role.`, edgeDiagnosticSpan(nodesById, graphEdge, fallbackSpan), {
    edge: graphEdge.kind,
    from: graphEdge.from,
    to: graphEdge.to,
    from_kind: sourceNode?.kind ?? null,
    to_kind: targetNode?.kind ?? null,
    supported_roles: [
      { from_kind: "Type", to_kind: "Goal" },
      { from_kind: "Goal", to_kind: "Memory" },
    ],
  });
}

function validateGraphCompletesEdgeRole(nodesById, graphEdge, sourceNode, targetNode, fallbackSpan) {
  if (sourceNode?.kind === "Goal" && targetNode?.kind === "Completion") {
    return null;
  }
  return error("INTENT_GRAPH_COMPLETE_INVALID", `completes edge '${graphEdge.from}' to '${graphEdge.to}' must connect a Goal node to a Completion node.`, edgeDiagnosticSpan(nodesById, graphEdge, fallbackSpan), {
    edge: graphEdge.kind,
    from: graphEdge.from,
    to: graphEdge.to,
    from_kind: sourceNode?.kind ?? null,
    to_kind: targetNode?.kind ?? null,
    supported_roles: [
      { from_kind: "Goal", to_kind: "Completion" },
    ],
  });
}

function validateGraphProducesEdgeRole(nodesById, graphEdge, sourceNode, targetNode, fallbackSpan) {
  if (sourceNode?.kind === "Step" && targetNode?.kind === "Completion") {
    return null;
  }
  return error("INTENT_GRAPH_PRODUCE_INVALID", `produces edge '${graphEdge.from}' to '${graphEdge.to}' must connect a Step node to a Completion node.`, edgeDiagnosticSpan(nodesById, graphEdge, fallbackSpan), {
    edge: graphEdge.kind,
    from: graphEdge.from,
    to: graphEdge.to,
    from_kind: sourceNode?.kind ?? null,
    to_kind: targetNode?.kind ?? null,
    supported_roles: [
      { from_kind: "Step", to_kind: "Completion" },
    ],
  });
}

function validateGraphPlansEdgeRole(nodesById, graphEdge, sourceNode, targetNode, fallbackSpan) {
  if (sourceNode?.kind === "Goal" && targetNode?.kind === "Step") {
    return null;
  }
  return error("INTENT_GRAPH_PLAN_INVALID", `plans edge '${graphEdge.from}' to '${graphEdge.to}' must connect a Goal node to a Step node.`, edgeDiagnosticSpan(nodesById, graphEdge, fallbackSpan), {
    edge: graphEdge.kind,
    from: graphEdge.from,
    to: graphEdge.to,
    from_kind: sourceNode?.kind ?? null,
    to_kind: targetNode?.kind ?? null,
    supported_roles: [
      { from_kind: "Goal", to_kind: "Step" },
    ],
  });
}

function validateGraphGatesEdgeRole(nodesById, graphEdge, sourceNode, targetNode, fallbackSpan) {
  if (sourceNode?.kind === "Check" && targetNode?.kind === "Goal") {
    return null;
  }
  return error("INTENT_GRAPH_GATE_INVALID", `gates edge '${graphEdge.from}' to '${graphEdge.to}' must connect a Check node to a Goal node.`, edgeDiagnosticSpan(nodesById, graphEdge, fallbackSpan), {
    edge: graphEdge.kind,
    from: graphEdge.from,
    to: graphEdge.to,
    from_kind: sourceNode?.kind ?? null,
    to_kind: targetNode?.kind ?? null,
    supported_roles: [
      { from_kind: "Check", to_kind: "Goal" },
    ],
  });
}

function validateGraphVerifiesEdgeRole(nodesById, graphEdge, sourceNode, targetNode, fallbackSpan) {
  if (sourceNode?.kind === "Check" && targetNode?.kind === "Completion") {
    return null;
  }
  return error("INTENT_GRAPH_VERIFY_INVALID", `verifies edge '${graphEdge.from}' to '${graphEdge.to}' must connect a Check node to a Completion node.`, edgeDiagnosticSpan(nodesById, graphEdge, fallbackSpan), {
    edge: graphEdge.kind,
    from: graphEdge.from,
    to: graphEdge.to,
    from_kind: sourceNode?.kind ?? null,
    to_kind: targetNode?.kind ?? null,
    supported_roles: [
      { from_kind: "Check", to_kind: "Completion" },
    ],
  });
}

function validateGraphRequestsEdgeRole(nodesById, graphEdge, sourceNode, targetNode, fallbackSpan) {
  if (targetNode?.kind === "Effect") {
    return null;
  }
  return error("INTENT_GRAPH_REQUEST_INVALID", `requests edge '${graphEdge.from}' to '${graphEdge.to}' must target an Effect node.`, edgeDiagnosticSpan(nodesById, graphEdge, fallbackSpan), {
    edge: graphEdge.kind,
    from: graphEdge.from,
    to: graphEdge.to,
    from_kind: sourceNode?.kind ?? null,
    to_kind: targetNode?.kind ?? null,
    supported_roles: [
      { to_kind: "Effect" },
    ],
  });
}

function validateGraphAuthorizesEdgeRole(nodesById, graphEdge, sourceNode, targetNode, fallbackSpan) {
  const targetIsAuthorizationTarget = targetNode?.kind === "Effect" || targetNode?.kind === "Check" || targetNode?.kind === "Context";
  const targetIsCapabilityOwner = targetNode?.kind === "Goal" && sourceNode?.kind === "Capability";
  if (targetIsAuthorizationTarget || targetIsCapabilityOwner) {
    return null;
  }
  return error("INTENT_GRAPH_AUTHORIZE_INVALID", `authorizes edge '${graphEdge.from}' to '${graphEdge.to}' must connect a supported authorization role.`, edgeDiagnosticSpan(nodesById, graphEdge, fallbackSpan), {
    edge: graphEdge.kind,
    from: graphEdge.from,
    to: graphEdge.to,
    from_kind: sourceNode?.kind ?? null,
    to_kind: targetNode?.kind ?? null,
    supported_roles: [
      { from_kind: "Capability", to_kind: "Goal" },
      { to_kind: "Effect" },
      { to_kind: "Check" },
      { to_kind: "Context" },
    ],
  });
}

function validateGraphPolicy(graphNode, graphSpan) {
  if (graphNode.kind !== "Policy") {
    return null;
  }
  const policyKindIsValid = graphNode.data.policyKind === "timeout" || graphNode.data.policyKind === "retry";
  const policyIsNonempty = typeof graphNode.data.policy === "string" && graphNode.data.policy.trim() !== "";
  const ownerStepIsNonempty = typeof graphNode.data.ownerStep === "string" && graphNode.data.ownerStep.trim() !== "";
  if (policyKindIsValid && policyIsNonempty && ownerStepIsNonempty) {
    return null;
  }
  return error("INTENT_GRAPH_POLICY_INVALID", `policy '${graphNode.label}' must carry valid step execution policy data.`, graphNode.span ?? graphSpan, {
    policy: graphNode.label,
    policy_id: graphNode.id,
    policy_kind: typeof graphNode.data.policyKind === "string" ? graphNode.data.policyKind : null,
    owner_step: typeof graphNode.data.ownerStep === "string" ? graphNode.data.ownerStep : null,
    policy_kind_is_valid: policyKindIsValid,
    policy_is_nonempty: policyIsNonempty,
    owner_step_is_nonempty: ownerStepIsNonempty,
  });
}

function validateGraphApproval(graphNode, graphSpan) {
  if (graphNode.kind !== "Approval") {
    return null;
  }
  const approvalIsNonempty = typeof graphNode.data.approval === "string" && graphNode.data.approval.trim() !== "";
  const ownerStepIsNonempty = typeof graphNode.data.ownerStep === "string" && graphNode.data.ownerStep.trim() !== "";
  if (approvalIsNonempty && ownerStepIsNonempty) {
    return null;
  }
  return error("INTENT_GRAPH_APPROVAL_INVALID", `approval '${graphNode.label}' must carry valid step approval gate data.`, graphNode.span ?? graphSpan, {
    approval: graphNode.label,
    approval_id: graphNode.id,
    approval_gate: typeof graphNode.data.approval === "string" ? graphNode.data.approval : null,
    owner_step: typeof graphNode.data.ownerStep === "string" ? graphNode.data.ownerStep : null,
    approval_is_nonempty: approvalIsNonempty,
    owner_step_is_nonempty: ownerStepIsNonempty,
  });
}

function validateGraphCheckpoint(graphNode, graphSpan) {
  if (graphNode.kind !== "Checkpoint") {
    return null;
  }
  const checkpointIsNonempty = typeof graphNode.data.checkpoint === "string" && graphNode.data.checkpoint.trim() !== "";
  const ownerStepIsNonempty = typeof graphNode.data.ownerStep === "string" && graphNode.data.ownerStep.trim() !== "";
  if (checkpointIsNonempty && ownerStepIsNonempty) {
    return null;
  }
  return error("INTENT_GRAPH_CHECKPOINT_INVALID", `checkpoint '${graphNode.label}' must carry valid step checkpoint data.`, graphNode.span ?? graphSpan, {
    checkpoint: graphNode.label,
    checkpoint_id: graphNode.id,
    checkpoint_value: typeof graphNode.data.checkpoint === "string" ? graphNode.data.checkpoint : null,
    owner_step: typeof graphNode.data.ownerStep === "string" ? graphNode.data.ownerStep : null,
    checkpoint_is_nonempty: checkpointIsNonempty,
    owner_step_is_nonempty: ownerStepIsNonempty,
  });
}

function validateGraphEffect(graphNode, graphSpan) {
  if (graphNode.kind !== "Effect") {
    return null;
  }
  const familyIsNonempty = typeof graphNode.data.family === "string" && graphNode.data.family.trim() !== "";
  const actionIsNonempty = typeof graphNode.data.action === "string" && graphNode.data.action.trim() !== "";
  const argsIsObject = isPlainObject(graphNode.data.args);
  const argKindsIsObject = isPlainObject(graphNode.data.argKinds);
  const argSpansIsObject = isPlainObject(graphNode.data.argSpans);
  const argSpansAreValid = argSpansIsObject && Object.values(graphNode.data.argSpans).every(isSpan);
  const approvalRequiredIsBoolean = typeof graphNode.data.approvalRequired === "boolean";
  if (familyIsNonempty && actionIsNonempty && argsIsObject && argKindsIsObject && argSpansAreValid && approvalRequiredIsBoolean) {
    return null;
  }
  return error("INTENT_GRAPH_EFFECT_INVALID", `effect '${graphNode.label}' must carry valid runtime adapter data.`, graphNode.span ?? graphSpan, {
    effect: graphNode.label,
    effect_id: graphNode.id,
    family: typeof graphNode.data.family === "string" ? graphNode.data.family : null,
    action: typeof graphNode.data.action === "string" ? graphNode.data.action : null,
    family_is_nonempty: familyIsNonempty,
    action_is_nonempty: actionIsNonempty,
    args_is_object: argsIsObject,
    arg_kinds_is_object: argKindsIsObject,
    arg_spans_is_object: argSpansIsObject,
    arg_spans_are_valid: argSpansAreValid,
    approval_required_is_boolean: approvalRequiredIsBoolean,
  });
}

function validateGraphContext(graphNode, graphSpan) {
  if (graphNode.kind !== "Context") {
    return null;
  }
  const sourceIsNonempty = typeof graphNode.data.source === "string" && graphNode.data.source.trim() !== "";
  const expressionIsNonempty = typeof graphNode.data.expression === "string" && graphNode.data.expression.trim() !== "";
  const argsIsObject = isPlainObject(graphNode.data.args);
  const argKindsIsObject = isPlainObject(graphNode.data.argKinds);
  const argSpansIsObject = isPlainObject(graphNode.data.argSpans);
  const argSpansAreValid = argSpansIsObject && Object.values(graphNode.data.argSpans).every(isSpan);
  if (sourceIsNonempty && expressionIsNonempty && argsIsObject && argKindsIsObject && argSpansAreValid) {
    return null;
  }
  return error("INTENT_GRAPH_CONTEXT_INVALID", `context '${graphNode.label}' must carry valid runtime source data.`, graphNode.span ?? graphSpan, {
    context: graphNode.label,
    context_id: graphNode.id,
    source: typeof graphNode.data.source === "string" ? graphNode.data.source : null,
    expression: typeof graphNode.data.expression === "string" ? graphNode.data.expression : null,
    source_is_nonempty: sourceIsNonempty,
    expression_is_nonempty: expressionIsNonempty,
    args_is_object: argsIsObject,
    arg_kinds_is_object: argKindsIsObject,
    arg_spans_is_object: argSpansIsObject,
    arg_spans_are_valid: argSpansAreValid,
  });
}

function validateGraphCheck(graphNode, graphSpan) {
  if (graphNode.kind !== "Check") {
    return null;
  }
  const requirementIsNonempty = typeof graphNode.data.requirement === "string" && graphNode.data.requirement.trim() !== "";
  const scopeIsValid = graphNode.data.scope === undefined || graphNode.data.scope === "goal" || graphNode.data.scope === "step";
  const ownerStepIsValid = graphNode.data.scope !== "step"
    || (typeof graphNode.data.ownerStep === "string" && graphNode.data.ownerStep.trim() !== "");
  const assertionIsValid = graphNode.data.scope !== "step"
    || (typeof graphNode.data.assertion === "string" && graphNode.data.assertion.trim() !== "");
  const effectIsPresent = graphNode.data.effect !== undefined;
  const effectIsObject = !effectIsPresent || isPlainObject(graphNode.data.effect);
  const effect = effectIsObject && effectIsPresent ? graphNode.data.effect : {};
  const effectFamilyIsNonempty = !effectIsPresent || (typeof effect.family === "string" && effect.family.trim() !== "");
  const effectActionIsNonempty = !effectIsPresent || (typeof effect.action === "string" && effect.action.trim() !== "");
  const effectArgsIsObject = !effectIsPresent || isPlainObject(effect.args);
  const effectArgKindsIsObject = !effectIsPresent || isPlainObject(effect.argKinds);
  const effectArgSpansIsObject = !effectIsPresent || isPlainObject(effect.argSpans);
  const effectArgSpansAreValid = !effectIsPresent || (effectArgSpansIsObject && Object.values(effect.argSpans).every(isSpan));
  if (
    requirementIsNonempty
    && scopeIsValid
    && ownerStepIsValid
    && assertionIsValid
    && effectIsObject
    && effectFamilyIsNonempty
    && effectActionIsNonempty
    && effectArgsIsObject
    && effectArgKindsIsObject
    && effectArgSpansAreValid
  ) {
    return null;
  }
  return error("INTENT_GRAPH_CHECK_INVALID", `check '${graphNode.label}' must carry valid runtime check data.`, graphNode.span ?? graphSpan, {
    check: graphNode.label,
    check_id: graphNode.id,
    scope: typeof graphNode.data.scope === "string" ? graphNode.data.scope : null,
    requirement_is_nonempty: requirementIsNonempty,
    scope_is_valid: scopeIsValid,
    owner_step_is_valid: ownerStepIsValid,
    assertion_is_valid: assertionIsValid,
    effect_is_object: effectIsObject,
    effect_family_is_nonempty: effectFamilyIsNonempty,
    effect_action_is_nonempty: effectActionIsNonempty,
    effect_args_is_object: effectArgsIsObject,
    effect_arg_kinds_is_object: effectArgKindsIsObject,
    effect_arg_spans_is_object: effectArgSpansIsObject,
    effect_arg_spans_are_valid: effectArgSpansAreValid,
  });
}

function validateGraphNodeTrust(graphNode, graphSpan) {
  const trustTargets = [];
  if (graphNode.kind === "Context" || graphNode.kind === "Effect") {
    trustTargets.push({ path: "data.trust", trust: graphNode.data.trust });
  }
  if (graphNode.kind === "Check" && graphNode.data.effect) {
    trustTargets.push({ path: "data.effect.trust", trust: graphNode.data.effect.trust });
  }
  const malformedTrust = trustTargets.find((target) => !isTrustRecord(target.trust));
  if (!malformedTrust) {
    return null;
  }
  return error("INTENT_GRAPH_TRUST_INVALID", `${graphNode.kind} '${graphNode.label}' must carry valid trust metadata.`, graphNode.span ?? graphSpan, {
    node: graphNode.label,
    node_id: graphNode.id,
    node_kind: graphNode.kind,
    trust_path: malformedTrust.path,
    trust_zone: isPlainObject(malformedTrust.trust) ? malformedTrust.trust.zone ?? null : null,
    trust_source: isPlainObject(malformedTrust.trust) ? malformedTrust.trust.source ?? null : null,
    zone_is_supported: isPlainObject(malformedTrust.trust) && TRUST_ZONES.has(malformedTrust.trust.zone),
    source_is_nonempty: isPlainObject(malformedTrust.trust) && typeof malformedTrust.trust.source === "string" && malformedTrust.trust.source.trim() !== "",
    argument_is_valid: isPlainObject(malformedTrust.trust)
      && (malformedTrust.trust.argument === undefined || (typeof malformedTrust.trust.argument === "string" && malformedTrust.trust.argument.trim() !== "")),
  });
}

function isTrustRecord(value) {
  return isPlainObject(value)
    && TRUST_ZONES.has(value.zone)
    && typeof value.source === "string"
    && value.source.trim() !== ""
    && (value.argument === undefined || (typeof value.argument === "string" && value.argument.trim() !== ""));
}

function requiresCapabilityAuthorization(graphNode) {
  return graphNode.kind === "Effect"
    || (graphNode.kind === "Check" && Boolean(graphNode.data?.effect))
    || (graphNode.kind === "Context" && requiresContextAuthorization(graphNode));
}

function requiresContextAuthorization(graphNode) {
  return graphNode.data?.source === "web" || graphNode.data?.source === "documents";
}

function validateGraphContextInforms(nodesById, outgoingEdgesByNode, graphNode, fallbackSpan) {
  const ownerGoalId = parentNodeId(graphNode.id, ":context:");
  const ownerGoal = ownerGoalId ? nodesById.get(ownerGoalId) : null;
  if (ownerGoal?.kind !== "Goal") {
    return null;
  }
  const outgoingEdges = outgoingEdgesByNode.get(graphNode.id) ?? [];
  const informsEdges = outgoingEdges.filter((graphEdge) => graphEdge.kind === "informs");
  const ownerGoalInformsEdges = informsEdges.filter((graphEdge) => graphEdge.to === ownerGoalId);
  if (ownerGoalInformsEdges.length === 1 && informsEdges.length === ownerGoalInformsEdges.length) {
    return null;
  }
  return error("INTENT_GRAPH_CONTEXT_INFORMS_INVALID", `context '${graphNode.label}' must inform its owning goal.`, graphNode.span ?? fallbackSpan, {
    context: graphNode.label,
    context_id: graphNode.id,
    owner_goal_id: ownerGoalId,
    informs_edges: informsEdges.length,
    owner_goal_informs_edges: ownerGoalInformsEdges.length,
  });
}

function validateGraphCheckGate(nodesById, outgoingEdgesByNode, graphNode, fallbackSpan) {
  const ownerGoalId = checkOwnerGoalId(graphNode.id);
  const expectedCompletionId = ownerGoalId ? `${ownerGoalId}:completion` : null;
  const outgoingEdges = outgoingEdgesByNode.get(graphNode.id) ?? [];
  const gateEdges = outgoingEdges.filter((graphEdge) => graphEdge.kind === "gates");
  const ownerGateEdges = gateEdges.filter((graphEdge) => graphEdge.to === ownerGoalId && nodesById.get(graphEdge.to)?.kind === "Goal");
  const verifyEdges = outgoingEdges.filter((graphEdge) => graphEdge.kind === "verifies");
  const ownerVerifyEdges = verifyEdges.filter((graphEdge) => {
    return graphEdge.to === expectedCompletionId && nodesById.get(graphEdge.to)?.kind === "Completion";
  });
  const isStepScoped = graphNode.data?.scope === "step";
  const verifyContractIsValid = isStepScoped
    ? verifyEdges.length === 0
    : ownerVerifyEdges.length === 1 && verifyEdges.length === ownerVerifyEdges.length;

  if (ownerGateEdges.length === 1 && gateEdges.length === ownerGateEdges.length && verifyContractIsValid) {
    return null;
  }

  return error("INTENT_GRAPH_CHECK_GATE_INVALID", `check '${graphNode.label}' must have valid gates and verifies edges for its scope.`, graphNode.span ?? fallbackSpan, {
    check: graphNode.label,
    check_id: graphNode.id,
    scope: isStepScoped ? "step" : "goal",
    owner_goal_id: ownerGoalId,
    completion_id: expectedCompletionId,
    gate_edges: gateEdges.length,
    owner_goal_gate_edges: ownerGateEdges.length,
    verify_edges: verifyEdges.length,
    owner_completion_verify_edges: ownerVerifyEdges.length,
  });
}

function checkOwnerGoalId(checkId) {
  const ownerStepId = parentNodeId(checkId, ":requirement:");
  if (ownerStepId) {
    return parentNodeId(ownerStepId, ":step:");
  }
  return parentNodeId(checkId, ":verify:");
}

function validateGraphInputSupply(nodesById, outgoingEdgesByNode, graphNode, fallbackSpan) {
  const ownerGoalId = parentNodeId(graphNode.id, ":input:");
  const ownerGoal = ownerGoalId ? nodesById.get(ownerGoalId) : null;
  if (ownerGoal?.kind !== "Goal") {
    return null;
  }
  const outgoingEdges = outgoingEdgesByNode.get(graphNode.id) ?? [];
  const supplyEdges = outgoingEdges.filter((graphEdge) => graphEdge.kind === "supplies");
  const ownerSupplyEdges = supplyEdges.filter((graphEdge) => graphEdge.to === ownerGoalId);
  if (ownerSupplyEdges.length === 1 && supplyEdges.length === ownerSupplyEdges.length) {
    return null;
  }
  return error("INTENT_GRAPH_INPUT_SUPPLY_INVALID", `goal input '${graphNode.label}' must supply its owning goal.`, graphNode.span ?? fallbackSpan, {
    input: graphNode.label,
    input_id: graphNode.id,
    owner_goal_id: ownerGoalId,
    supply_edges: supplyEdges.length,
    owner_goal_supply_edges: ownerSupplyEdges.length,
  });
}

function stepAttachment(graphNode) {
  if (graphNode.kind === "Check" && graphNode.data?.scope === "step") {
    return { ownerStepId: parentNodeId(graphNode.id, ":requirement:"), edgeKind: "requires", direction: "outgoing" };
  }
  if (graphNode.kind === "Approval") {
    return { ownerStepId: parentNodeId(graphNode.id, ":approval:"), edgeKind: "approves", direction: "outgoing" };
  }
  if (graphNode.kind === "Checkpoint") {
    return { ownerStepId: parentNodeId(graphNode.id, ":checkpoint:"), edgeKind: "checkpoints", direction: "incoming" };
  }
  if (graphNode.kind === "Policy" && graphNode.data?.policyKind === "timeout") {
    return { ownerStepId: parentNodeId(graphNode.id, ":timeout:"), edgeKind: "timeouts", direction: "outgoing" };
  }
  if (graphNode.kind === "Policy" && graphNode.data?.policyKind === "retry") {
    return { ownerStepId: parentNodeId(graphNode.id, ":retry:"), edgeKind: "retries", direction: "outgoing" };
  }
  return null;
}

function parentNodeId(nodeId, marker) {
  const markerIndex = nodeId.indexOf(marker);
  return markerIndex === -1 ? null : nodeId.slice(0, markerIndex);
}

function validateGoalCompletionOwnership(nodesById, outgoingEdgesByNode, goalNode, fallbackSpan) {
  const expectedCompletionId = `${goalNode.id}:completion`;
  const completionNode = nodesById.get(expectedCompletionId);
  const outgoingCompletesEdges = (outgoingEdgesByNode.get(goalNode.id) ?? []).filter((graphEdge) => graphEdge.kind === "completes");
  const expectedCompletesEdges = outgoingCompletesEdges.filter((graphEdge) => graphEdge.to === expectedCompletionId);
  const invalidCompletesTargets = outgoingCompletesEdges
    .filter((graphEdge) => graphEdge.to !== expectedCompletionId)
    .map((graphEdge) => graphEdge.to);

  if (completionNode?.kind === "Completion" && expectedCompletesEdges.length === 1 && invalidCompletesTargets.length === 0) {
    return null;
  }

  return error("INTENT_GRAPH_GOAL_COMPLETION_INVALID", `goal '${goalNode.label}' must own one completion node and one completes edge to it.`, goalNode.span ?? fallbackSpan, {
    goal: goalNode.label,
    goal_id: goalNode.id,
    completion_id: expectedCompletionId,
    completion_node_kind: completionNode?.kind ?? null,
    completes_edges: outgoingCompletesEdges.length,
    expected_completes_edges: expectedCompletesEdges.length,
    invalid_completes_targets: invalidCompletesTargets,
  });
}

function validateGoalStepSequence(graph, nodesById, incomingEdgesByNode, goalNode, fallbackSpan) {
  const stepNodes = graph.nodes.filter((candidate) => candidate.kind === "Step" && candidate.id.startsWith(`${goalNode.id}:step:`));
  if (stepNodes.length === 0) {
    return null;
  }

  const stepIds = new Set(stepNodes.map((stepNode) => stepNode.id));
  const incomingPrecedesCounts = new Map(stepNodes.map((stepNode) => [stepNode.id, 0]));
  const outgoingPrecedesTargets = new Map(stepNodes.map((stepNode) => [stepNode.id, []]));
  const precedesEdges = [];
  const malformedPrecedesEdges = [];

  for (const graphEdge of graph.edges) {
    if (graphEdge.kind !== "precedes") {
      continue;
    }
    const fromIsStep = stepIds.has(graphEdge.from);
    const toIsStep = stepIds.has(graphEdge.to);
    if (!fromIsStep && !toIsStep) {
      continue;
    }
    if (!fromIsStep || !toIsStep) {
      malformedPrecedesEdges.push(graphEdge);
      continue;
    }
    precedesEdges.push(graphEdge);
    incomingPrecedesCounts.set(graphEdge.to, (incomingPrecedesCounts.get(graphEdge.to) ?? 0) + 1);
    outgoingPrecedesTargets.get(graphEdge.from).push(graphEdge.to);
  }

  const headStepIds = stepNodes
    .filter((stepNode) => (incomingPrecedesCounts.get(stepNode.id) ?? 0) === 0)
    .map((stepNode) => stepNode.id);
  const tailStepIds = stepNodes
    .filter((stepNode) => (outgoingPrecedesTargets.get(stepNode.id) ?? []).length === 0)
    .map((stepNode) => stepNode.id);
  const branchStepIds = stepNodes
    .filter((stepNode) => {
      return (incomingPrecedesCounts.get(stepNode.id) ?? 0) > 1 || (outgoingPrecedesTargets.get(stepNode.id) ?? []).length > 1;
    })
    .map((stepNode) => stepNode.id);

  const orderedStepIds = [];
  if (headStepIds.length === 1) {
    const seen = new Set();
    let cursor = headStepIds[0];
    while (cursor && !seen.has(cursor)) {
      orderedStepIds.push(cursor);
      seen.add(cursor);
      const targets = outgoingPrecedesTargets.get(cursor) ?? [];
      cursor = targets.length === 1 ? targets[0] : null;
    }
  }

  const completionId = `${goalNode.id}:completion`;
  const completionProducerStepIds = (incomingEdgesByNode.get(completionId) ?? [])
    .filter((graphEdge) => graphEdge.kind === "produces" && stepIds.has(graphEdge.from))
    .map((graphEdge) => graphEdge.from);
  const expectedTailStepId = tailStepIds.length === 1 ? tailStepIds[0] : null;
  const producerIsTail = completionProducerStepIds.length !== 1 || expectedTailStepId === null
    ? true
    : completionProducerStepIds[0] === expectedTailStepId;
  const validChain = stepNodes.length === 1
    ? precedesEdges.length === 0 && malformedPrecedesEdges.length === 0
    : precedesEdges.length === stepNodes.length - 1
      && malformedPrecedesEdges.length === 0
      && headStepIds.length === 1
      && tailStepIds.length === 1
      && branchStepIds.length === 0
      && orderedStepIds.length === stepNodes.length;

  if (validChain && producerIsTail) {
    return null;
  }

  return error("INTENT_GRAPH_STEP_SEQUENCE_INVALID", `goal '${goalNode.label}' steps must form one linear precedes chain ending at the completion producer.`, goalNode.span ?? fallbackSpan, {
    goal: goalNode.label,
    goal_id: goalNode.id,
    step_count: stepNodes.length,
    precedes_edges: precedesEdges.length,
    expected_precedes_edges: Math.max(stepNodes.length - 1, 0),
    head_step_ids: headStepIds,
    tail_step_ids: tailStepIds,
    branch_step_ids: branchStepIds,
    malformed_precedes_edges: malformedPrecedesEdges.map((graphEdge) => ({ from: graphEdge.from, to: graphEdge.to })),
    ordered_step_ids: orderedStepIds,
    completion_producer_step_ids: completionProducerStepIds,
    expected_completion_producer_step_id: expectedTailStepId,
  });
}

function invariantGoalId(invariantId) {
  const marker = ":invariant:";
  const markerIndex = invariantId.indexOf(marker);
  return markerIndex === -1 ? null : invariantId.slice(0, markerIndex);
}

function validateGraphInvariantConstraint(nodesById, outgoingEdgesByNode, graphNode, fallbackSpan) {
  const ownerGoalId = invariantGoalId(graphNode.id);
  const outgoingEdges = outgoingEdgesByNode.get(graphNode.id) ?? [];
  const constraintEdges = outgoingEdges.filter((graphEdge) => graphEdge.kind === "constrains");
  const ownerConstraintEdges = constraintEdges.filter((graphEdge) => {
    return graphEdge.to === ownerGoalId && nodesById.get(graphEdge.to)?.kind === "Goal";
  });
  if (ownerConstraintEdges.length === 1 && constraintEdges.length === ownerConstraintEdges.length) {
    return null;
  }
  return error("INTENT_GRAPH_INVARIANT_CONSTRAINT_INVALID", `invariant '${graphNode.label}' must have one constrains edge to its owning goal.`, graphNode.span ?? fallbackSpan, {
    invariant: graphNode.label,
    invariant_id: graphNode.id,
    owner_goal_id: ownerGoalId,
    constrains_edges: constraintEdges.length,
    owner_goal_constrains_edges: ownerConstraintEdges.length,
  });
}

function invariantGuardTargetIds(nodes, goalId) {
  const completionId = `${goalId}:completion`;
  return nodes
    .filter((candidate) => {
      if (candidate.id === completionId) {
        return true;
      }
      if (!candidate.id.startsWith(`${goalId}:step:`)) {
        return false;
      }
      return candidate.kind === "Effect"
        || candidate.kind === "Checkpoint"
        || candidate.kind === "Policy"
        || (candidate.kind === "Check" && candidate.data?.scope === "step");
    })
    .map((candidate) => candidate.id);
}

function edgeDiagnosticSpan(nodesById, graphEdge, fallbackSpan) {
  return nodesById.get(graphEdge.from)?.span ?? nodesById.get(graphEdge.to)?.span ?? fallbackSpan;
}

function parseParameters(text, file, lineNumber, rawLine = text) {
  if (!text.trim()) {
    return [];
  }
  let searchColumn = 0;
  return text.split(",").map((part) => {
    const trimmed = part.trim();
    const match = trimmed.match(/^([a-z][a-z0-9_]*)(?:\s*:\s*([A-Za-z][A-Za-z0-9_<>, ]*))?$/);
    if (!match) {
      throw parseError(file, lineNumber, text, `invalid parameter '${trimmed}'`);
    }
    const rawIndex = rawLine.indexOf(trimmed, searchColumn);
    const startColumn = rawIndex >= 0 ? rawIndex + 1 : 1;
    searchColumn = rawIndex >= 0 ? rawIndex + trimmed.length : searchColumn;
    return {
      name: match[1],
      type: match[2]?.trim() ?? null,
      span: span(file, lineNumber, startColumn, lineNumber, startColumn + trimmed.length),
    };
  });
}

function parseOutputTypeSpan(outputType, file, lineNumber, rawLine) {
  if (!outputType) {
    return null;
  }
  const arrowIndex = rawLine.indexOf("->");
  if (arrowIndex < 0) {
    return null;
  }
  const afterArrow = rawLine.slice(arrowIndex + 2);
  const firstOutputChar = afterArrow.search(/\S/);
  if (firstOutputChar < 0) {
    return null;
  }
  const startColumn = arrowIndex + 2 + firstOutputChar + 1;
  return span(file, lineNumber, startColumn, lineNumber, startColumn + outputType.length);
}

function extractTypeNames(typeRef) {
  return [...typeRef.matchAll(/\b[A-Z][A-Za-z0-9_]*\b/g)].map((match) => match[0]);
}

function parseCapabilityGrant(text, grantSpan) {
  const trimmed = text.trim();
  const match = trimmed.match(/^([a-z][a-z0-9_]*)\s+([a-z][a-z0-9_]*)\s*:\s*"([^"]*)"$/);
  if (match) {
    return {
      action: match[1],
      key: match[2],
      value: match[3],
      raw: trimmed,
      span: grantSpan,
    };
  }

  const dottedCall = trimmed.match(/^[a-z][a-z0-9_]*\.([a-z][a-z0-9_]*)\((.*)\)$/);
  if (dottedCall) {
    const { values: args } = parseCallArgs(dottedCall[2]);
    const key = args.paths ? "path"
      : args.commands ? "command"
        : args.domains ? "domain"
          : args.branches ? "branch"
            : args.remotes ? "remote"
              : args.path ? "path"
                : args.command ? "command"
                  : args.domain ? "domain"
                    : args.branch ? "branch"
                      : args.remote ? "remote"
                        : null;
    const value = args.paths ?? args.commands ?? args.domains ?? args.branches ?? args.remotes
      ?? args.path ?? args.command ?? args.domain ?? args.branch ?? args.remote ?? null;
    if (key && typeof value === "string") {
      return {
        action: dottedCall[1],
        key,
        value,
        raw: trimmed,
        span: grantSpan,
      };
    }
  }

  return null;
}

function hasApprovalRequired(lines) {
  return lines.some((line) => /^approval\s+required$/.test(line.text) || /^approval\s*:\s*required$/.test(line.text));
}

function parseCallArgs(text, file = null, lineNumber = 1, raw = text) {
  const values = {};
  const kinds = {};
  const spans = {};
  for (const match of text.matchAll(/([a-z][a-z0-9_]*)\s*:\s*"([^"]*)"/g)) {
    values[match[1]] = match[2];
    kinds[match[1]] = "string";
    const argumentSpan = callArgSpan(file, lineNumber, raw, text, match.index, match[0]);
    if (argumentSpan) spans[match[1]] = argumentSpan;
  }
  for (const match of text.matchAll(/([a-z][a-z0-9_]*)\s*:\s*([a-z][a-z0-9_]*)\b/g)) {
    if (!(match[1] in values)) {
      values[match[1]] = match[2];
      kinds[match[1]] = "identifier";
      const argumentSpan = callArgSpan(file, lineNumber, raw, text, match.index, match[0]);
      if (argumentSpan) spans[match[1]] = argumentSpan;
    }
  }
  const positional = /\(\s*"([^"]*)"/.exec(text);
  if (positional) {
    values._0 = positional[1];
    kinds._0 = "string";
    const argumentSpan = callArgSpan(file, lineNumber, raw, text, positional.index + positional[0].indexOf("\""), `"${positional[1]}"`);
    if (argumentSpan) spans._0 = argumentSpan;
  }
  return { values, kinds, spans };
}

function callArgSpan(file, lineNumber, raw, text, textIndex, fallbackText) {
  if (!file) {
    return null;
  }
  const rawOffset = raw.indexOf(text);
  const startIndex = (rawOffset >= 0 ? rawOffset : 0) + textIndex;
  return span(file, lineNumber, startIndex + 1, lineNumber, startIndex + fallbackText.length + 1);
}

function normalizeTypeRef(typeRef) {
  return typeRef ? typeRef.replace(/\s+/g, "") : null;
}

function addProducer(producersByType, typeRef, nodeId, producerSpan) {
  const normalized = normalizeTypeRef(typeRef);
  if (!normalized) {
    return;
  }
  const producers = producersByType.get(normalized) ?? [];
  producers.push({
    id: nodeId,
    span: producerSpan,
  });
  producersByType.set(normalized, producers);
}

function latestProducer(producersByType, typeRef) {
  const producers = producersByType.get(normalizeTypeRef(typeRef));
  return producers?.at(-1) ?? null;
}

function collectBlock(lines, startIndex, file) {
  const startRaw = lines[startIndex];
  const startLine = startIndex + 1;
  const startText = stripComment(startRaw).trim();
  const header = startText.replace(/\s*\{\s*$/, "").trim();
  let depth = countChar(startRaw, "{") - countChar(startRaw, "}");
  if (depth <= 0) {
    throw parseError(file, startLine, startRaw, "expected block opening brace");
  }
  const body = [];
  let index = startIndex + 1;
  for (; index < lines.length; index += 1) {
    const raw = lines[index];
    depth += countChar(raw, "{") - countChar(raw, "}");
    if (depth <= 0) {
      return {
        header,
        body,
        startLine,
        endLine: index + 1,
        nextIndex: index + 1,
      };
    }
    body.push({
      lineNumber: index + 1,
      text: raw,
    });
  }
  throw parseError(file, startLine, startRaw, "unterminated block");
}

function collectInlineBlock(entries, startIndex, file) {
  const start = entries[startIndex];
  let depth = countChar(start.text, "{") - countChar(start.text, "}");
  const body = [];
  let index = startIndex + 1;
  for (; index < entries.length; index += 1) {
    const entry = entries[index];
    depth += countChar(entry.text, "{") - countChar(entry.text, "}");
    if (depth <= 0) {
      return {
        body,
        startLine: start.lineNumber,
        endLine: entry.lineNumber,
        nextIndex: index + 1,
      };
    }
    body.push(entry);
  }
  throw parseError(file, start.lineNumber, start.text, "unterminated block");
}

function meaningfulLines(entries) {
  return entries.map((entry) => ({
    lineNumber: entry.lineNumber,
    raw: entry.text,
    text: stripComment(entry.text).trim(),
  })).filter((entry) => entry.text && entry.text !== "}");
}

function statementNode(kind, value, file, lineNumber, raw) {
  return {
    kind,
    value,
    span: lineSpan(file, lineNumber, raw),
  };
}

function spannedText(value, line, file) {
  const textStart = line.raw.indexOf(line.text);
  const columnOffset = textStart >= 0 ? textStart : Math.max(line.raw.search(/\S/), 0);
  const valueStart = line.text.indexOf(value);
  const startColumn = columnOffset + valueStart + 1;
  return {
    raw: value,
    span: span(file, line.lineNumber, startColumn, line.lineNumber, startColumn + value.length),
  };
}

function verificationEffect(requirement) {
  const shellCall = requirement.value.match(/\bshell\s*\(\s*(?:"([^"]*)"|command\s*:\s*"([^"]*)")\s*\)/);
  const command = shellCall?.[1] ?? shellCall?.[2] ?? null;
  if (!command) {
    return null;
  }
  const rawPrefix = " ".repeat(requirement.span.start.column + "require ".length - 1);
  const parsedArgs = parseCallArgs(shellCall[0], requirement.span.file, requirement.span.start.line, `${rawPrefix}${requirement.value}`);
  return {
    kind: "EffectUse",
    name: "shell",
    family: "shell",
    action: "run",
    args: {
      command,
    },
    argKinds: {
      command: "string",
    },
    argSpans: {
      command: parsedArgs.spans.command ?? parsedArgs.spans._0,
    },
    expression: requirement.value,
    span: requirement.span,
  };
}

function verificationImpureEffect(requirement) {
  for (const match of requirement.value.matchAll(/\b([A-Za-z][A-Za-z0-9_.]*)\s*\(([^)]*)\)/g)) {
    const name = match[1];
    if (name === "shell") {
      continue;
    }
    if (!isKnownEffectCall(name)) {
      continue;
    }
    const rawPrefix = " ".repeat(requirement.span.start.column + "require ".length - 1);
    const parsedArgs = parseCallArgs(match[0], requirement.span.file, requirement.span.start.line, `${rawPrefix}${requirement.value}`);
    return {
      kind: "EffectUse",
      name,
      family: effectFamily(name),
      action: effectAction(name),
      args: parsedArgs.values,
      argKinds: parsedArgs.kinds,
      argSpans: parsedArgs.spans,
      expression: match[0],
      span: requirementValueSpan(requirement, match.index, match[0].length),
    };
  }
  return null;
}

function requirementValueSpan(requirement, startIndex, length) {
  const startColumn = requirement.span.start.column + "require ".length + startIndex;
  return span(requirement.span.file, requirement.span.start.line, startColumn, requirement.span.start.line, startColumn + length);
}

function isKnownEffectCall(name) {
  if (/^[A-Z][A-Za-z0-9_.]*$/.test(name)) {
    return true;
  }
  return ["file", "fs", "web", "http", "git", "deploy", "ticket"].includes(effectFamily(name));
}

function error(code, message, nodeSpan, data = {}) {
  return {
    severity: "error",
    code,
    message,
    span: nodeSpan,
    ...data,
  };
}

function node(id, kind, label, nodeSpan, data = {}) {
  return {
    id,
    kind,
    label,
    span: nodeSpan,
    data,
  };
}

function edge(from, to, kind, data = undefined) {
  return data ? { from, to, kind, data } : { from, to, kind };
}

function parseError(file, lineNumber, raw, message) {
  const err = new Error(message);
  err.diagnostic = error("INTENT_PARSE_ERROR", message, lineSpan(file, lineNumber, raw));
  return err;
}

function lineSpan(file, lineNumber, raw) {
  const first = raw.search(/\S/);
  return span(file, lineNumber, first >= 0 ? first + 1 : 1, lineNumber, raw.length + 1);
}

function span(file, startLine, startColumn, endLine = startLine, endColumn = startColumn) {
  const normalizedFile = path.normalize(file);
  const lineOffsets = sourceLineOffsets.get(normalizedFile);
  const start = { line: startLine, column: startColumn };
  const end = { line: endLine, column: endColumn };
  if (lineOffsets) {
    start.offset = offsetFor(lineOffsets, startLine, startColumn);
    end.offset = offsetFor(lineOffsets, endLine, endColumn);
  }
  return {
    file: normalizedFile,
    start,
    end,
  };
}

function computeLineOffsets(source) {
  const offsets = [0];
  for (let index = 0; index < source.length; index += 1) {
    if (source[index] === "\n") {
      offsets.push(index + 1);
    }
  }
  return offsets;
}

function offsetFor(lineOffsets, line, column) {
  return (lineOffsets[line - 1] ?? 0) + column - 1;
}

function lastColumn(lines) {
  const last = lines.at(-1) ?? "";
  return last.length + 1;
}

function stripComment(line) {
  let inString = false;
  let escaped = false;
  for (let index = 0; index < line.length; index += 1) {
    const char = line[index];
    if (escaped) {
      escaped = false;
      continue;
    }
    if (char === "\\") {
      escaped = true;
      continue;
    }
    if (char === "\"") {
      inString = !inString;
      continue;
    }
    if (char === "#" && !inString) {
      return line.slice(0, index);
    }
  }
  return line;
}

function countChar(text, char) {
  return [...text].filter((candidate) => candidate === char).length;
}

function firstWord(text) {
  return text.trim().split(/\s+/)[0] ?? "";
}

function slugify(text) {
  return text.toLowerCase().replace(/[^a-z0-9]+/g, "_").replace(/^_+|_+$/g, "") || "goal";
}

function capabilityFamily(name) {
  return name.split(/[.(\s]/)[0] || name;
}

function contextTrust(source) {
  if (["repo", "file", "documents", "workspace"].includes(source)) {
    return { zone: "trusted", source: "local_context" };
  }
  if (["web", "http", "browser"].includes(source)) {
    return { zone: "untrusted", source: "external_context" };
  }
  return { zone: "unknown", source: "context" };
}

function contextAccess(context) {
  if (["web", "http", "browser"].includes(context.source)) {
    const url = context.args.url ?? context.args.urls ?? context.args._0;
    const args = {
      ...context.args,
    };
    const argKinds = {
      ...context.argKinds,
    };
    if (url) {
      args.url ??= url;
      argKinds.url ??= context.argKinds.url ?? context.argKinds.urls ?? context.argKinds._0;
    }
    const domain = context.args.domain ?? context.args.domains ?? (url ? domainFromUrl(url) : null);
    if (domain) {
      args.domain ??= domain;
      argKinds.domain ??= context.argKinds.domain ?? context.argKinds.domains ?? (url ? context.argKinds._0 : undefined);
    }
    return {
      kind: "ContextAccess",
      name: context.expression,
      family: "web",
      action: "read",
      args,
      argKinds,
      argSpans: context.argSpans,
      expression: context.expression,
      span: context.span,
    };
  }
  if (["documents", "doc", "file"].includes(context.source)) {
    const pathValue = context.args.path ?? context.args.paths ?? context.args._0;
    const args = {
      ...context.args,
    };
    const argKinds = {
      ...context.argKinds,
    };
    if (pathValue) {
      args.path ??= pathValue;
      argKinds.path ??= context.argKinds.path ?? context.argKinds.paths ?? context.argKinds._0;
    }
    return {
      kind: "ContextAccess",
      name: context.expression,
      family: "file",
      action: "read",
      args,
      argKinds,
      argSpans: context.argSpans,
      expression: context.expression,
      span: context.span,
    };
  }
  return null;
}

function effectFamily(name) {
  const normalized = name.replace(/^Effect\./, "");
  if (/^(FileRead|ReadFile|fs\.read|file\.read)/.test(normalized)) return "file";
  if (/^(FileWrite|WriteFile|fs\.write|file\.write)/.test(normalized)) return "file";
  if (/^(ShellExec|shell\.exec|Command)/.test(normalized)) return "shell";
  if (/^(Http|Web|web\.read|http\.request)/.test(normalized)) return "web";
  if (/^(Git|git\.)/.test(normalized)) return "git";
  if (/^(Deploy|deploy\.)/.test(normalized)) return "deploy";
  if (/^(Ticket|ticket\.)/.test(normalized)) return "ticket";
  if (/^(SecretRead|Secret|secret\.)/.test(normalized)) return "secret";
  return normalized.split(/[.(]/)[0].toLowerCase();
}

function effectAction(name) {
  const normalized = name.replace(/^Effect\./, "");
  if (/^(FileRead|ReadFile|fs\.read|file\.read)/.test(normalized)) return "read";
  if (/^(FileWrite|WriteFile|fs\.write|file\.write)/.test(normalized)) return "write";
  if (/^(ShellExec|shell\.exec|Command)/.test(normalized)) return "run";
  if (/^(Http|Web|web\.read|http\.request)/.test(normalized)) return "read";
  if (/^(GitPush|git\.push)/.test(normalized)) return "push";
  if (/^(GitCommit|git\.commit)/.test(normalized)) return "commit";
  if (/^(Deploy|deploy\.)/.test(normalized)) return "deploy";
  if (/^(Ticket|ticket\.)/.test(normalized)) return "update";
  if (/^(SecretRead|Secret|secret\.read)/.test(normalized)) return "read";
  return null;
}

function isEffectAuthorized(effect, capabilities) {
  return capabilities.some((capability) => isFamilyMatch(effect.family, capability.family));
}

function approvalRequiredCapability(effect, capabilities) {
  return capabilities.find((capability) => {
    return capability.approvalRequired
      && isFamilyMatch(effect.family, capability.family)
      && !getCapabilityDenial(effect, [capability]);
  }) ?? null;
}

function isFamilyMatch(effectName, capabilityName) {
  if (effectName === capabilityName) return true;
  if (effectName === "file" && capabilityName === "fs") return true;
  if (effectName === "web" && capabilityName === "http") return true;
  if (effectName === "http" && capabilityName === "web") return true;
  return false;
}

function getCapabilityDenial(effect, capabilities) {
  const familyCapabilities = capabilities.filter((capability) => isFamilyMatch(effect.family, capability.family));
  if (familyCapabilities.length === 0) {
    return null;
  }

  const argumentsToCheck = effectArguments(effect);
  if (!effect.action || argumentsToCheck.length === 0) {
    return null;
  }

  for (const argument of argumentsToCheck) {
    const candidateGrants = familyCapabilities.flatMap((capability) => capability.grants ?? [])
      .filter((grant) => grant.action === effect.action && grant.key === argument.key);

    if (candidateGrants.length === 0) {
      return {
        message: `effect '${effect.name}' has no '${effect.action} ${argument.key}' capability grant.`,
        argument: argument.key,
        value: argument.value,
        allowed: [],
      };
    }

    if (candidateGrants.some((grant) => isGrantMatch(argument, grant))) {
      continue;
    }

    return {
      message: `effect '${effect.name}' ${argument.key} '${argument.value}' is outside declared capability grants.`,
      argument: argument.key,
      value: argument.value,
      allowed: candidateGrants.map((grant) => grant.value),
    };
  }

  return null;
}

function getTrustFlowDiagnostic(effect) {
  if (effect.family !== "shell") {
    return null;
  }
  const commandKey = effect.args.command ? "command" : effect.args._0 ? "_0" : null;
  if (!commandKey) {
    return null;
  }
  if (effect.argKinds?.[commandKey] === "string") {
    return null;
  }
  return {
    message: `effect '${effect.name}' uses nonliteral shell command '${effect.args[commandKey]}'.`,
    argument: commandKey === "_0" ? "command" : commandKey,
    value: effect.args[commandKey],
    trust: "untrusted",
  };
}

function getInvariantViolation(effect, invariants, contexts = []) {
  for (const invariant of invariants) {
    if (invariant.kind !== "Deny") {
      continue;
    }
    const rule = invariant.value.trim();
    if (rule === "secret_write") {
      const pathArgument = effectArguments(effect).find((argument) => argument.key === "path");
      if (effect.family === "file" && effect.action === "write" && pathArgument && isSecretPath(pathArgument.value)) {
        return {
          message: `invariant '${invariant.value}' denies effect '${effect.name}' path '${pathArgument.value}'.`,
          invariant,
          argument: "path",
          value: pathArgument.value,
        };
      }
      continue;
    }
    if (rule === "unrelated_file_write") {
      const pathArgument = effectArguments(effect).find((argument) => argument.key === "path");
      const repoRoots = repoContextRoots(contexts);
      if (effect.family === "file" && effect.action === "write" && pathArgument && repoRoots.length > 0 && !isPathUnderRepoRoots(pathArgument.value, repoRoots)) {
        return {
          message: `invariant '${invariant.value}' denies effect '${effect.name}' path '${pathArgument.value}' outside repository context.`,
          invariant,
          argument: "path",
          value: pathArgument.value,
        };
      }
      continue;
    }
    if (rule !== "production_deploy") {
      continue;
    }
    const target = effectArguments(effect).find((argument) => argument.key === "target");
    if (effect.family === "deploy" && target?.value === "production") {
      return {
        message: `invariant '${invariant.value}' denies effect '${effect.name}' target '${target.value}'.`,
        invariant,
        argument: "target",
        value: target.value,
      };
    }
  }
  return null;
}

function isSecretPath(value) {
  const basename = path.posix.basename(normalizePathLike(value)).toLowerCase();
  return basename === ".env" || /\b(secret|token|credential|key|password)s?\b/.test(basename);
}

function repoContextRoots(contexts) {
  return contexts
    .filter((context) => context.source === "repo")
    .map((context) => context.args.path ?? context.args.paths ?? context.args._0)
    .filter((value) => typeof value === "string")
    .map((value) => normalizePathLike(value));
}

function isPathUnderRepoRoots(value, repoRoots) {
  const normalized = normalizePathLike(value);
  if (normalized.startsWith("../") || normalized.startsWith("/")) {
    return false;
  }
  return repoRoots.some((root) => {
    if (root === "") {
      return true;
    }
    return normalized === root || normalized.startsWith(`${root}/`);
  });
}

function effectTrust(effect) {
  if (effect.family !== "shell") {
    return { zone: "unknown", source: "effect" };
  }
  const commandKey = effect.args.command ? "command" : effect.args._0 ? "_0" : null;
  if (!commandKey) {
    return { zone: "unknown", source: "missing_command" };
  }
  if (effect.argKinds?.[commandKey] === "string") {
    return { zone: "trusted", source: "literal", argument: "command" };
  }
  return { zone: "untrusted", source: effect.argKinds?.[commandKey] ?? "unknown", argument: "command" };
}

function effectArgument(effect) {
  return effectArguments(effect)[0] ?? null;
}

function effectArgumentSpan(effect, argument) {
  if (!argument) {
    return effect.span;
  }
  const argSpans = effect.argSpans ?? {};
  if (argSpans[argument.argument] || argSpans[argument.key]) {
    return argSpans[argument.argument] ?? argSpans[argument.key];
  }
  const aliases = {
    path: ["paths", "_0"],
    command: ["commands", "_0"],
    domain: ["domains", "url", "urls", "_0"],
    branch: ["branches", "_0"],
    remote: ["remotes", "_0"],
    message: ["_0"],
    target: ["environment", "env", "_0"],
    name: ["names", "_0"],
    id: ["_0"],
  };
  for (const key of aliases[argument.argument] ?? aliases[argument.key] ?? []) {
    if (argSpans[key]) {
      return argSpans[key];
    }
  }
  return effect.span;
}

function effectArguments(effect) {
  if (effect.family === "file") {
    const value = effect.args.path ?? effect.args.paths ?? effect.args._0;
    return value ? [{ key: "path", value }] : [];
  }
  if (effect.family === "shell") {
    const value = effect.args.command ?? effect.args.commands ?? effect.args._0;
    return value ? [{ key: "command", value }] : [];
  }
  if (effect.family === "web" || effect.family === "http") {
    const domain = effect.args.domain ?? effect.args.domains;
    if (domain) {
      return [{ key: "domain", value: normalizeDomain(domain) }];
    }
    const url = effect.args.url ?? effect.args.urls ?? effect.args._0;
    const host = url ? domainFromUrl(url) : null;
    return url ? [{ key: "domain", value: host ?? url }] : [];
  }
  if (effect.family === "git") {
    return [
      effect.args.branch ? { key: "branch", value: normalizeRefName(effect.args.branch) } : null,
      effect.args.remote ? { key: "remote", value: normalizeRefName(effect.args.remote) } : null,
      effect.args.message ? { key: "message", value: normalizeCommitMessage(effect.args.message) } : null,
    ].filter(Boolean);
  }
  if (effect.family === "deploy") {
    const value = effect.args.target ?? effect.args.environment ?? effect.args.env ?? effect.args._0;
    return value ? [{ key: "target", value: normalizeDeployTarget(value) }] : [];
  }
  if (effect.family === "secret") {
    const value = effect.args.name ?? effect.args.names ?? effect.args._0;
    return value ? [{ key: "name", value: normalizeSecretName(value) }] : [];
  }
  if (effect.family === "ticket") {
    const value = effect.args.id ?? effect.args._0;
    return value ? [{ key: "id", value: normalizeTicketRef(value) }] : [];
  }
  return [];
}

function isGrantMatch(argument, grant) {
  if (argument.key === "path") {
    return isPathGrantMatch(argument.value, grant.value);
  }
  if (argument.key === "domain") {
    return isDomainGrantMatch(argument.value, grant.value);
  }
  if (argument.key === "branch" || argument.key === "remote") {
    return normalizeRefName(argument.value) === normalizeRefName(grant.value);
  }
  if (argument.key === "message") {
    return normalizeCommitMessage(argument.value) === normalizeCommitMessage(grant.value);
  }
  if (argument.key === "target") {
    return normalizeDeployTarget(argument.value) === normalizeDeployTarget(grant.value);
  }
  if (argument.key === "name") {
    return normalizeSecretName(argument.value) === normalizeSecretName(grant.value);
  }
  if (argument.key === "id") {
    return normalizeTicketRef(argument.value) === normalizeTicketRef(grant.value);
  }
  return normalizeCommand(argument.value) === normalizeCommand(grant.value);
}

function isPathGrantMatch(value, pattern) {
  const normalizedValue = normalizePathLike(value);
  const normalizedPattern = normalizePathLike(pattern);
  if (normalizedValue.startsWith("../") || normalizedPattern.startsWith("../")) {
    return false;
  }
  if (normalizedPattern.endsWith("/**")) {
    const prefix = normalizedPattern.slice(0, -3);
    return normalizedValue === prefix || normalizedValue.startsWith(`${prefix}/`);
  }
  if (normalizedPattern.includes("*")) {
    const escaped = normalizedPattern.split("*").map(escapeRegExp).join("[^/]*");
    return new RegExp(`^${escaped}$`).test(normalizedValue);
  }
  return normalizedValue === normalizedPattern;
}

function normalizePathLike(value) {
  const normalized = path.posix.normalize(value.replace(/\\/g, "/").replace(/^\.\//, ""));
  return normalized === "." ? "" : normalized.replace(/\/+$/g, "");
}

function normalizeCommand(value) {
  return value.trim().replace(/\s+/g, " ");
}

function normalizeRefName(value) {
  return value.trim().replace(/^refs\/heads\//, "");
}

function normalizeCommitMessage(value) {
  return value.trim().replace(/\s+/g, " ");
}

function normalizeDeployTarget(value) {
  return value.trim().toLowerCase();
}

function normalizeSecretName(value) {
  return value.trim();
}

function normalizeTicketRef(value) {
  return value.trim().toUpperCase();
}

function unquote(value) {
  const trimmed = value.trim();
  return trimmed.startsWith("\"") && trimmed.endsWith("\"") && trimmed.length >= 2
    ? trimmed.slice(1, -1)
    : trimmed;
}

function domainFromUrl(value) {
  try {
    const url = new URL(value);
    if (url.protocol !== "http:" && url.protocol !== "https:") {
      return null;
    }
    return normalizeDomain(url.hostname);
  } catch {
    return null;
  }
}

function normalizeDomain(value) {
  return value.trim().toLowerCase().replace(/\.$/, "");
}

function isDomainGrantMatch(value, pattern) {
  const normalizedValue = normalizeDomain(value);
  const normalizedPattern = normalizeDomain(pattern);
  if (normalizedPattern.startsWith("*.")) {
    const suffix = normalizedPattern.slice(2);
    return normalizedValue.endsWith(`.${suffix}`) && normalizedValue !== suffix;
  }
  return normalizedValue === normalizedPattern;
}

function escapeRegExp(value) {
  return value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

if (import.meta.url === `file://${process.argv[1]}`) {
  process.exitCode = main(process.argv.slice(2));
}

export {
  VERSION,
  buildGraph,
  checkIntent,
  parseIntent,
  validateGraph,
};
