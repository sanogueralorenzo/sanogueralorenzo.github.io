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

  const goal = {
    kind: "Goal",
    name: named ? named[1] : slugify(quoted[1]),
    title: named ? null : quoted[1],
    parameters: named ? parseParameters(named[2], file, startLine) : [],
    outputType: named && named[3] ? named[3].trim() : null,
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
      goal.context.push(statementNode("ContextSource", line.slice("context ".length), file, entry.lineNumber, entry.text));
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
      goal.context.push(statementNode("ContextSource", line.text, file, line.lineNumber, line.raw));
    }
    return;
  }

  if (normalized === "capability") {
    if (header !== "capability" && header.startsWith("capability ")) {
      const name = header.slice("capability ".length).trim();
      const capability = {
        kind: "Capability",
        family: capabilityFamily(name),
        action: null,
        name,
        constraints: meaningfulLines(body).map((line) => line.text),
        grants: meaningfulLines(body).map((line) => parseCapabilityGrant(line.text)).filter(Boolean),
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
  const effects = [];
  const requirements = [];
  if (match[3]) {
    const effectOutput = match[3].trim().match(/^Effect<\s*([A-Za-z][A-Za-z0-9_.]*)/);
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
  }
  return {
    kind: "Step",
    name: match[1],
    parameters: parseParameters(match[2] ?? "", file, startLine),
    outputType: match[3] ? match[3].trim() : null,
    effects,
    requirements,
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
    grants: [parseCapabilityGrant(normalized)].filter(Boolean),
    span: lineSpan(file, lineNumber, raw),
  };
}

function parseEffectUse(text, file, lineNumber, raw) {
  const parsedArgs = parseCallArgs(text);
  const name = text.match(/^([A-Za-z][A-Za-z0-9_.]*)/)?.[1] ?? text;
  return {
    kind: "EffectUse",
    name,
    family: effectFamily(name),
    action: effectAction(name),
    args: parsedArgs.values,
    argKinds: parsedArgs.kinds,
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

    validateMemory(goal, diagnostics);

    validateGoalTypes(goal, declaredTypes, diagnostics);
    validateStepBindings(goal, diagnostics);
    validateVerifyRequirements(goal, diagnostics);

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
          diagnostics.push(error("INTENT_TRUST_FLOW_UNSAFE", trustFlow.message, effect.span, {
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
          diagnostics.push(error("INTENT_CAPABILITY_DENIED", denial.message, effect.span, {
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
      if (!retention.subject?.raw || !retention.until?.raw) {
        diagnostics.push(error("INTENT_MEMORY_RETENTION_INVALID", `memory '${memory.name ?? memory.scope}' has invalid retention rule '${retention.raw}'.`, retention.span, {
          memory: memory.name ?? memory.scope,
          scope: memory.scope,
          retention: retention.raw,
        }));
      }
    }
  }
}

function validateGoalTypes(goal, declaredTypes, diagnostics) {
  const seenParameters = new Map();
  for (const parameter of goal.parameters) {
    if (seenParameters.has(parameter.name)) {
      diagnostics.push(error("INTENT_NAME_DUPLICATE", `parameter '${parameter.name}' is already declared in goal '${goal.name}'.`, goal.span, {
        name: parameter.name,
      }));
    }
    seenParameters.set(parameter.name, parameter);
    validateTypeRef(parameter.type, goal.span, declaredTypes, diagnostics);
  }
  validateTypeRef(goal.outputType, goal.span, declaredTypes, diagnostics);

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

    const parameterNames = new Set();
    for (const parameter of step.parameters) {
      if (parameterNames.has(parameter.name)) {
        diagnostics.push(error("INTENT_NAME_DUPLICATE", `parameter '${parameter.name}' is already declared in step '${step.name}'.`, step.span, {
          name: parameter.name,
        }));
      }
      parameterNames.add(parameter.name);
      validateTypeRef(parameter.type, step.span, declaredTypes, diagnostics);
    }
    validateTypeRef(step.outputType, step.span, declaredTypes, diagnostics);
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

function validateVerifyRequirements(goal, diagnostics) {
  for (const requirement of goal.verify) {
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
      diagnostics.push(error("INTENT_VERIFY_UNDECLARED", `verify requirement '${requirement.value}' must be declared by a matching capability grant.`, requirement.span, {
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
    }));

    const producersByType = new Map();
    for (const parameter of goal.parameters) {
      const inputId = `${goalId}:input:${parameter.name}`;
      nodes.push(node(inputId, "Input", parameter.name, goal.span, {
        scope: "goal",
        type: parameter.type,
      }));
      edges.push(edge(inputId, goalId, "supplies"));
      addProducer(producersByType, parameter.type, inputId);
    }

    for (const [index, context] of goal.context.entries()) {
      const id = `${goalId}:context:${index}`;
      nodes.push(node(id, "Context", context.value, context.span));
      edges.push(edge(id, goalId, "informs"));
    }

    for (const [index, capability] of goal.capabilities.entries()) {
      const id = `${goalId}:capability:${index}`;
      nodes.push(node(id, "Capability", capability.name, capability.span, {
        family: capability.family,
        action: capability.action,
        grants: capability.grants,
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
    for (const [index, step] of goal.steps.entries()) {
      const id = `${goalId}:step:${step.name || index}`;
      nodes.push(node(id, "Step", step.name, step.span, {
        inputs: step.parameters,
        outputType: step.outputType,
        effects: step.effects.map((effect) => effect.name),
      }));
      edges.push(edge(goalId, id, "plans"));
      if (previousStepId) {
        edges.push(edge(previousStepId, id, "precedes"));
      }
      previousStepId = id;
      lastStepId = id;

      for (const parameter of step.parameters) {
        const stepInputId = `${id}:input:${parameter.name}`;
        nodes.push(node(stepInputId, "Input", parameter.name, step.span, {
          scope: "step",
          type: parameter.type,
        }));
        edges.push(edge(stepInputId, id, "requires", {
          parameter: parameter.name,
          type: normalizeTypeRef(parameter.type),
        }));

        const producerId = latestProducer(producersByType, parameter.type);
        if (producerId) {
          edges.push(edge(producerId, stepInputId, "data", {
            parameter: parameter.name,
            type: normalizeTypeRef(parameter.type),
          }));
        }
      }

      for (const [effectIndex, effectUse] of step.effects.entries()) {
        const effectId = `${id}:effect:${effectIndex}`;
        nodes.push(node(effectId, "Effect", effectUse.name, effectUse.span, {
          family: effectUse.family,
          action: effectUse.action,
          args: effectUse.args,
          argKinds: effectUse.argKinds,
          trust: effectTrust(effectUse),
          expression: effectUse.expression,
        }));
        edges.push(edge(id, effectId, "requests"));
        for (const [capabilityIndex, capability] of goal.capabilities.entries()) {
          if (isFamilyMatch(effectUse.family, capability.family) && !getCapabilityDenial(effectUse, [capability])) {
            edges.push(edge(`${goalId}:capability:${capabilityIndex}`, effectId, "authorizes"));
          }
        }
      }

      addProducer(producersByType, step.outputType, id);
    }

    const completionId = `${goalId}:completion`;
    nodes.push(node(completionId, "Completion", goal.name, goal.span, {
      outputType: goal.outputType,
    }));
    edges.push(edge(goalId, completionId, "completes"));
    if (lastStepId) {
      edges.push(edge(lastStepId, completionId, "produces", {
        type: normalizeTypeRef(goal.steps.at(-1)?.outputType),
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
      }));
      edges.push(edge(id, goalId, "constrains"));
      edges.push(edge(id, completionId, "guards"));
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

function parseParameters(text, file, lineNumber) {
  if (!text.trim()) {
    return [];
  }
  return text.split(",").map((part) => {
    const trimmed = part.trim();
    const match = trimmed.match(/^([a-z][a-z0-9_]*)(?:\s*:\s*([A-Za-z][A-Za-z0-9_<>, ]*))?$/);
    if (!match) {
      throw parseError(file, lineNumber, text, `invalid parameter '${trimmed}'`);
    }
    return {
      name: match[1],
      type: match[2]?.trim() ?? null,
    };
  });
}

function extractTypeNames(typeRef) {
  return [...typeRef.matchAll(/\b[A-Z][A-Za-z0-9_]*\b/g)].map((match) => match[0]);
}

function parseCapabilityGrant(text) {
  const trimmed = text.trim();
  const match = trimmed.match(/^([a-z][a-z0-9_]*)\s+([a-z][a-z0-9_]*)\s*:\s*"([^"]*)"$/);
  if (match) {
    return {
      action: match[1],
      key: match[2],
      value: match[3],
      raw: trimmed,
    };
  }

  const dottedCall = trimmed.match(/^[a-z][a-z0-9_]*\.([a-z][a-z0-9_]*)\((.*)\)$/);
  if (dottedCall) {
    const { values: args } = parseCallArgs(dottedCall[2]);
    const key = args.paths ? "path" : args.commands ? "command" : args.path ? "path" : args.command ? "command" : null;
    const value = args.paths ?? args.commands ?? args.path ?? args.command ?? null;
    if (key && typeof value === "string") {
      return {
        action: dottedCall[1],
        key,
        value,
        raw: trimmed,
      };
    }
  }

  return null;
}

function parseCallArgs(text) {
  const values = {};
  const kinds = {};
  for (const match of text.matchAll(/([a-z][a-z0-9_]*)\s*:\s*"([^"]*)"/g)) {
    values[match[1]] = match[2];
    kinds[match[1]] = "string";
  }
  for (const match of text.matchAll(/([a-z][a-z0-9_]*)\s*:\s*([a-z][a-z0-9_]*)\b/g)) {
    if (!(match[1] in values)) {
      values[match[1]] = match[2];
      kinds[match[1]] = "identifier";
    }
  }
  const positional = text.match(/\(\s*"([^"]*)"/);
  if (positional) {
    values._0 = positional[1];
    kinds._0 = "string";
  }
  return { values, kinds };
}

function normalizeTypeRef(typeRef) {
  return typeRef ? typeRef.replace(/\s+/g, "") : null;
}

function addProducer(producersByType, typeRef, nodeId) {
  const normalized = normalizeTypeRef(typeRef);
  if (!normalized) {
    return;
  }
  const producers = producersByType.get(normalized) ?? [];
  producers.push(nodeId);
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
    expression: requirement.value,
    span: requirement.span,
  };
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

function effectFamily(name) {
  const normalized = name.replace(/^Effect\./, "");
  if (/^(FileRead|ReadFile|fs\.read|file\.read)/.test(normalized)) return "file";
  if (/^(FileWrite|WriteFile|fs\.write|file\.write)/.test(normalized)) return "file";
  if (/^(ShellExec|shell\.exec|Command)/.test(normalized)) return "shell";
  if (/^(Http|Web|web\.read|http\.request)/.test(normalized)) return "web";
  if (/^(Git|git\.)/.test(normalized)) return "git";
  if (/^(Deploy|deploy\.)/.test(normalized)) return "deploy";
  if (/^(Ticket|ticket\.)/.test(normalized)) return "ticket";
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
  return null;
}

function isEffectAuthorized(effect, capabilities) {
  return capabilities.some((capability) => isFamilyMatch(effect.family, capability.family));
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

  const argument = effectArgument(effect);
  if (!effect.action || !argument) {
    return null;
  }

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
    return null;
  }

  return {
    message: `effect '${effect.name}' ${argument.key} '${argument.value}' is outside declared capability grants.`,
    argument: argument.key,
    value: argument.value,
    allowed: candidateGrants.map((grant) => grant.value),
  };
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
  if (effect.family === "file") {
    const value = effect.args.path ?? effect.args.paths ?? effect.args._0;
    return value ? { key: "path", value } : null;
  }
  if (effect.family === "shell") {
    const value = effect.args.command ?? effect.args.commands ?? effect.args._0;
    return value ? { key: "command", value } : null;
  }
  return null;
}

function isGrantMatch(argument, grant) {
  if (argument.key === "path") {
    return isPathGrantMatch(argument.value, grant.value);
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
