#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";
import process from "node:process";

const VERSION = "intent.static.v0";
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
        schema_version: "intent.check.v0",
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
      schema_version: "intent.check.v0",
      ok: false,
      diagnostics: [diagnostic],
    });
    return 1;
  }
}

function printJson(value) {
  process.stdout.write(`${JSON.stringify(value, null, 2)}\n`);
}

function parseIntent(source, file) {
  const lines = source.split(/\r?\n/);
  sourceLineOffsets.set(path.normalize(file), computeLineOffsets(source));
  const root = {
    schema_version: "intent.ast.v0",
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
      diagnostics.push(error("INTENT_VERIFY_IMPURE", `verify requirement '${requirement.value}' uses side-effect call '${impureEffect.name}'.`, requirement.span, {
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
      } : {}));
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

  return {
    schema_version: "intent.graph.v0",
    ast_schema_version: ast.schema_version,
    source: ast.source,
    package: ast.package?.name ?? "main",
    ok: diagnostics.length === 0,
    diagnostics,
    nodes,
    edges,
  };
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
    const parsedArgs = parseCallArgs(`(${match[2]})`);
    return {
      kind: "EffectUse",
      name,
      family: effectFamily(name),
      action: effectAction(name),
      args: parsedArgs.values,
      argKinds: parsedArgs.kinds,
      expression: match[0],
      span: requirement.span,
    };
  }
  return null;
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
};
