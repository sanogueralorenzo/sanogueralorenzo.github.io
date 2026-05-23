#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";
import process from "node:process";

const VERSION = "intent.static.v0";
const AST_SCHEMA_VERSION = "intent.ast.v0";
const CHECK_SCHEMA_VERSION = "intent.check.v0";
const GRAPH_SCHEMA_VERSION = "intent.graph.v0";
const EFFECT_CONTRACT_SCHEMA_VERSION = "intent.effect-contracts.v0";
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
  "cites",
  "plans",
  "precedes",
  "produces",
  "reads",
  "requests",
  "requires",
  "retries",
  "supplies",
  "timeouts",
  "verifies",
  "writes",
]);
const TRUST_ZONES = new Set(["trusted", "untrusted", "unknown"]);
const COMPLETION_PROVENANCE_REQUIREMENTS = new Set(["all_outputs_cited", "memory_provenance_complete"]);
const COMPLETION_PROVENANCE_INVARIANTS = new Set(["uncited_external_claim"]);
const COMPLETION_CHECKPOINT_REQUIREMENTS = new Set(["final_state_checkpointed", "checkpointed_final_state"]);
const COMPLETION_CHECKPOINT_INVARIANTS = new Set([]);
const EFFECT_CONTRACTS = [
  {
    id: "intent.effect.file.read.v0",
    family: "file",
    action: "read",
    match: { exact: ["FileRead", "ReadFile", "fs.read", "file.read"] },
    risk: "read_only",
    checkpoint: { requiredWhen: [], coverage: null },
    arguments: [
      { key: "path", aliases: ["path", "paths", "_0"], normalize: "path" },
    ],
  },
  {
    id: "intent.effect.file.write.v0",
    family: "file",
    action: "write",
    match: { exact: ["FileWrite", "WriteFile", "fs.write", "file.write"] },
    risk: "irreversible",
    checkpoint: { requiredWhen: ["deny:uncheckpointed_irreversible_effect"], coverage: "source_order_after_effect" },
    arguments: [
      {
        key: "path",
        aliases: ["path", "paths", "_0"],
        normalize: "path",
        trustSink: "file write path",
      },
    ],
  },
  {
    id: "intent.effect.shell.run.v0",
    family: "shell",
    action: "run",
    match: { exact: ["ShellExec", "shell.exec", "Command"] },
    risk: "irreversible",
    checkpoint: { requiredWhen: ["deny:uncheckpointed_irreversible_effect"], coverage: "source_order_after_effect" },
    arguments: [
      {
        key: "command",
        aliases: ["command", "commands", "_0"],
        normalize: "command",
        trustSink: "shell command",
      },
    ],
  },
  {
    id: "intent.effect.web.read.v0",
    family: "web",
    action: "read",
    match: { exact: ["Http", "HttpGet", "Web", "WebRead", "web.read", "http.get", "http.request"] },
    risk: "read_only",
    checkpoint: { requiredWhen: [], coverage: null },
    arguments: [
      { key: "domain", aliases: ["domain", "domains"], normalize: "domain" },
      { key: "domain", aliases: ["url", "urls", "_0"], normalize: "url_domain" },
    ],
  },
  {
    id: "intent.effect.git.push.v0",
    family: "git",
    action: "push",
    match: { exact: ["GitPush", "git.push"] },
    risk: "irreversible",
    checkpoint: { requiredWhen: ["deny:uncheckpointed_irreversible_effect"], coverage: "source_order_after_effect" },
    arguments: [
      {
        key: "branch",
        aliases: ["branch", "branches", "_0"],
        normalize: "ref",
        trustSink: "git branch",
      },
      {
        key: "remote",
        aliases: ["remote", "remotes"],
        normalize: "ref",
        trustSink: "git remote",
      },
    ],
  },
  {
    id: "intent.effect.git.commit.v0",
    family: "git",
    action: "commit",
    match: { exact: ["GitCommit", "git.commit"] },
    risk: "irreversible",
    checkpoint: { requiredWhen: ["deny:uncheckpointed_irreversible_effect"], coverage: "source_order_after_effect" },
    arguments: [
      {
        key: "message",
        aliases: ["message", "_0"],
        normalize: "commit_message",
        trustSink: "git commit message",
      },
    ],
  },
  {
    id: "intent.effect.deploy.deploy.v0",
    family: "deploy",
    action: "deploy",
    match: { exact: ["Deploy"], prefix: ["deploy."] },
    risk: "irreversible",
    checkpoint: { requiredWhen: ["deny:uncheckpointed_irreversible_effect"], coverage: "source_order_after_effect" },
    arguments: [
      {
        key: "target",
        aliases: ["target", "environment", "env", "_0"],
        normalize: "deploy_target",
        trustSink: "deploy target",
      },
    ],
  },
  {
    id: "intent.effect.ticket.update.v0",
    family: "ticket",
    action: "update",
    match: { exact: ["Ticket", "TicketUpdate"], prefix: ["ticket."] },
    risk: "irreversible",
    checkpoint: { requiredWhen: ["deny:uncheckpointed_irreversible_effect"], coverage: "source_order_after_effect" },
    arguments: [
      { key: "id", aliases: ["id", "_0"], normalize: "ticket", trustSink: "ticket id" },
    ],
  },
  {
    id: "intent.effect.secret.read.v0",
    family: "secret",
    action: "read",
    match: { exact: ["SecretRead", "Secret"], prefix: ["secret."] },
    risk: "read_only",
    checkpoint: { requiredWhen: [], coverage: null },
    arguments: [
      {
        key: "name",
        aliases: ["name", "names", "_0"],
        normalize: "secret",
        trustSink: "secret name",
      },
    ],
  },
];

function usage() {
  return [
    "Usage: node intent/bin/intent.mjs <parse|check|graph> <file.intent> [--json]",
    "       node intent/bin/intent.mjs contracts",
    "",
    "Commands:",
    "  parse      Parse Intent source and emit AST JSON.",
    "  check      Run static checks and emit diagnostics.",
    "  graph      Emit a machine-readable execution graph.",
    "  contracts  Emit the v0 effect adapter contract registry.",
  ].join("\n");
}

function main(argv) {
  const [command, file] = argv;
  if (!command || command === "--help" || command === "-h") {
    console.log(usage());
    return 0;
  }
  if (!["parse", "check", "graph", "contracts"].includes(command)) {
    console.error(`intent: unknown command '${command}'`);
    console.error(usage());
    return 2;
  }
  if (command === "contracts") {
    printJson(effectContractRegistry());
    return 0;
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
    && value.column >= 1
    && Number.isInteger(value.offset)
    && value.offset >= 0;
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
    imports: [],
    types: [],
    goals: [],
    span: span(file, 1, 1, lines.length, lastColumn(lines)),
  };

  let index = 0;
  let importsClosed = false;
  while (index < lines.length) {
    const raw = lines[index];
    const line = stripComment(raw).trim();
    const lineNumber = index + 1;
    if (!line) {
      index += 1;
      continue;
    }

    if (line.startsWith("package ")) {
      if (root.package) {
        throw parseError(file, lineNumber, raw, "duplicate package declaration");
      }
      root.package = parsePackageDecl(line, file, lineNumber, raw);
      index += 1;
      continue;
    }

    if (!root.package) {
      throw parseError(file, lineNumber, raw, `expected package declaration before '${line}'`);
    }

    if (line.startsWith("import ")) {
      if (importsClosed) {
        throw parseError(file, lineNumber, raw, "import declarations must appear before type or goal declarations");
      }
      root.imports.push(parseImportDecl(line, file, lineNumber, raw));
      index += 1;
      continue;
    }

    if (line.startsWith("type ")) {
      importsClosed = true;
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
      importsClosed = true;
      const parsed = collectBlock(lines, index, file);
      root.goals.push(parseGoal(parsed.header, parsed.body, file, parsed.startLine, parsed.endLine));
      index = parsed.nextIndex;
      continue;
    }

    throw parseError(file, lineNumber, raw, `unexpected top-level statement '${line}'`);
  }

  return root;
}

function parsePackageDecl(line, file, lineNumber, raw) {
  const match = line.match(/^package\s+([a-z][a-z0-9_]*(?:\.[a-z][a-z0-9_]*)*)$/);
  if (!match) {
    throw parseError(file, lineNumber, raw, `invalid package declaration '${line}'`);
  }
  return {
    kind: "Package",
    name: match[1],
    span: lineSpan(file, lineNumber, raw),
  };
}

function parseImportDecl(line, file, lineNumber, raw) {
  const match = line.match(/^import\s+([A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)*)$/);
  if (!match) {
    throw parseError(file, lineNumber, raw, `invalid import declaration '${line}'`);
  }
  return {
    kind: "Import",
    path: match[1],
    span: lineSpan(file, lineNumber, raw),
  };
}

function parseTypeDecl(line, file, lineNumber, raw, body = null) {
  const match = line.match(/^type\s+([A-Z][A-Za-z0-9_]*)(?:\s*=\s*(.*))?$/);
  if (!match) {
    throw parseError(file, lineNumber, raw, `invalid type declaration '${line}'`);
  }
  if (body !== null && body.trim() === "") {
    throw parseError(file, lineNumber, raw, `type declaration '${match[1]}' has an empty definition`);
  }
  if (body === null && match[2] !== undefined && match[2].trim() === "") {
    throw parseError(file, lineNumber, raw, `type declaration '${match[1]}' has an empty definition`);
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
        grants: lines.map((line) => parseCapabilityGrant(name, line.text, lineSpan(file, line.lineNumber, line.raw), file, line.lineNumber, line.raw)).filter(Boolean),
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
      keys: lines.filter((line) => line.text.startsWith("key ")).map((line) => parseMemoryKey(line, file)),
      statements: lines.map((line) => line.text),
      span: span(file, startLine, 1, endLine, 1),
    });
    return;
  }

  if (normalized === "plan") {
    goal.steps.push(...parsePlan(body, file, goal.rawBlocks));
    return;
  }

  if (normalized === "verify") {
    for (const line of meaningfulLines(body)) {
      if (line.text.startsWith("require ")) {
        goal.verify.push(statementNode("Require", line.text.slice("require ".length), file, line.lineNumber, line.raw));
      } else {
        goal.rawBlocks.push(statementNode("RawVerifyStatement", line.text, file, line.lineNumber, line.raw));
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
      } else {
        goal.rawBlocks.push(statementNode("RawInvariantStatement", line.text, file, line.lineNumber, line.raw));
      }
    }
  }
}

function parsePlan(body, file, rawStatements = []) {
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
      steps.push(parseStep(line.replace(/\s*\{\s*$/, ""), block.body, file, block.startLine, block.endLine, rawStatements));
      index = block.nextIndex;
      continue;
    }

    if (line.startsWith("step ")) {
      steps.push(parseStep(line, [], file, entry.lineNumber, entry.lineNumber, rawStatements));
      index += 1;
      continue;
    }

    rawStatements.push(statementNode("RawPlanStatement", line, file, entry.lineNumber, entry.text));
    index += 1;
  }
  return steps;
}

function parseStep(header, body, file, startLine, endLine, rawStatements = []) {
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
  const memoryAccesses = [];
  if (outputType) {
    const effectOutput = outputType.match(/^Effect<\s*([A-Za-z][A-Za-z0-9_.]*)/);
    if (effectOutput) {
      effects.push(parseEffectUse(effectOutput[1], file, startLine, header));
    }
  }
  for (const line of meaningfulLines(body)) {
    let parsed = false;
    if (line.text.startsWith("effect ")) {
      effects.push(parseEffectUse(line.text.slice("effect ".length), file, line.lineNumber, line.raw));
      parsed = true;
    }
    if (line.text.startsWith("require ")) {
      requirements.push(statementNode("Require", line.text.slice("require ".length), file, line.lineNumber, line.raw));
      parsed = true;
    }
    if (line.text.startsWith("checkpoint ")) {
      checkpoints.push(parseCheckpointStatement(line, file));
      parsed = true;
    }
    if (line.text.startsWith("approval ")) {
      approvals.push(parseApprovalStatement(line, file));
      parsed = true;
    }
    if (line.text.startsWith("timeout ")) {
      timeouts.push(parsePolicyStatement("Timeout", line, file, "timeout "));
      parsed = true;
    }
    if (line.text.startsWith("retry ")) {
      retries.push(parsePolicyStatement("Retry", line, file, "retry "));
      parsed = true;
    }
    if (line.text.startsWith("memory ")) {
      memoryAccesses.push(parseMemoryAccessStatement(line, file));
      parsed = true;
    }
    if (!parsed) {
      rawStatements.push(statementNode("RawStepStatement", line.text, file, line.lineNumber, line.raw));
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
    memoryAccesses,
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
    grants: [parseCapabilityGrant(family, normalized, lineSpan(file, lineNumber, raw), file, lineNumber, raw)].filter(Boolean),
    approvalRequired: /\bapproval\s*:\s*required\b|\bapproval\s+required\b/.test(normalized),
    span: lineSpan(file, lineNumber, raw),
  };
}

function parseContextSource(text, file, lineNumber, raw) {
  const source = text.match(/^([a-z][a-z0-9_]*)\s*\(/)?.[1] ?? firstWord(text);
  const parsedArgs = parseCallArgs(text, file, lineNumber, raw);
  const context = {
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
  const access = contextContractAccess(context);
  return {
    ...context,
    ...(access?.contractId ? {
      contractId: access.contractId,
      contractArguments: access.contractArguments,
    } : {}),
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

function parseMemoryKey(line, file) {
  const value = line.text.slice("key ".length).trim();
  const match = value.match(/^([A-Za-z][A-Za-z0-9_]*)(?:\s*:\s*([A-Za-z][A-Za-z0-9_<>, ]*))?$/);
  if (!match) {
    throw parseError(file, line.lineNumber, line.raw, `invalid memory key '${line.text}'`);
  }
  const name = match[1];
  const type = match[2]?.trim() ?? null;
  return {
    kind: "MemoryKey",
    name,
    type,
    typeSpan: parseMemoryKeyTypeSpan(type, file, line.lineNumber, line.raw),
    raw: line.text,
    span: lineSpan(file, line.lineNumber, line.raw),
  };
}

function parseMemoryKeyTypeSpan(type, file, lineNumber, rawLine) {
  if (!type) {
    return null;
  }
  const colonIndex = rawLine.indexOf(":");
  if (colonIndex < 0) {
    return null;
  }
  const afterColon = rawLine.slice(colonIndex + 1);
  const firstTypeChar = afterColon.search(/\S/);
  if (firstTypeChar < 0) {
    return null;
  }
  const startColumn = colonIndex + 1 + firstTypeChar + 1;
  return span(file, lineNumber, startColumn, lineNumber, startColumn + type.length);
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

function parseMemoryAccessStatement(line, file) {
  const value = line.text.slice("memory ".length).trim();
  const match = value.match(/^(read|write|cite)\s+([A-Za-z][A-Za-z0-9_]*)(?:\.([A-Za-z][A-Za-z0-9_]*))?$/);
  if (!match) {
    throw parseError(file, line.lineNumber, line.raw, `invalid memory access '${line.text}'`);
  }
  const memory = match[2];
  const key = match[3] ?? null;
  return {
    kind: "MemoryAccess",
    access: match[1],
    memory,
    key,
    target: key ? `${memory}.${key}` : memory,
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

    validateUnsupportedSyntax(goal, diagnostics);
    const invalidCapabilityGrantCount = validateCapabilityGrants(goal, diagnostics);
    validateEffectContracts(goal, diagnostics);
    validateMemory(goal, diagnostics);
    validateContextSources(goal, diagnostics);

    validateGoalTypes(goal, declaredTypes, diagnostics);
    validateStepBindings(goal, diagnostics);
    validateGoalCompletionType(goal, diagnostics);
    validateStepPolicies(goal, diagnostics);
    validateStepCheckpoints(goal, diagnostics);
    validateStepApprovals(goal, diagnostics);
    validateMemoryAccesses(goal, diagnostics);
    validateVerifyRequirements(goal, diagnostics);
    validateCompletionProvenance(goal, diagnostics);
    validateCompletionCheckpoint(goal, diagnostics);
    validateIrreversibleEffectCheckpoints(goal, diagnostics);
    validateApprovalRequirements(goal, diagnostics);

    const capabilities = goal.capabilities.map((capability) => capability.family);
    for (const step of goal.steps) {
      for (const effect of step.effects) {
        if (invalidCapabilityGrantCount > 0) {
          continue;
        }
        if (!isResolvedEffectContract(effect)) {
          continue;
        }
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

function validateCapabilityGrants(goal, diagnostics) {
  let invalidCount = 0;
  for (const capability of goal.capabilities) {
    for (const grant of capability.grants ?? []) {
      for (const argument of grant.args ?? []) {
        const contractArgument = effectContractArgumentForGrant({
          family: capability.family,
          action: grant.action,
          key: argument.key,
        });
        if (!contractArgument || argument.kind === "string" || argument.kind === "string_list") {
          continue;
        }
        invalidCount += 1;
        diagnostics.push(error("INTENT_CAPABILITY_GRANT_INVALID", `capability '${capability.name}' grant '${grant.raw}' argument '${argument.key}' must be a string or string list for v0 contract '${contractArgument.contract.id}'.`, argument.valueSpan ?? argument.span ?? grant.span ?? capability.span, {
          capability: capability.name,
          family: capability.family,
          action: grant.action,
          argument: argument.key,
          value: stringifyDiagnosticValue(argument.value),
          kind: argument.kind,
          contractId: contractArgument.contract.id,
        }));
      }
    }
  }
  return invalidCount;
}

function validateEffectContracts(goal, diagnostics) {
  for (const step of goal.steps) {
    for (const effect of step.effects) {
      const contract = effectContractForAccess(effect);
      if (contract) {
        const argumentDiagnostic = invalidEffectContractArgument(effect, contract);
        if (argumentDiagnostic) {
          diagnostics.push(error("INTENT_EFFECT_ARGUMENT_INVALID", `effect '${effect.name}' argument '${argumentDiagnostic.argument}' must be a string or trusted identifier for v0 contract '${contract.id}'.`, effectArgumentSpan(effect, argumentDiagnostic), {
            effect: effect.name,
            family: effect.family,
            action: effect.action,
            argument: argumentDiagnostic.argument,
            value: argumentDiagnostic.value,
            kind: argumentDiagnostic.kind,
            contractId: contract.id,
            step: step.name,
          }));
        }
        continue;
      }
      diagnostics.push(error("INTENT_EFFECT_UNKNOWN", `effect '${effect.name}' does not resolve to a v0 effect adapter contract.`, effect.span, {
        effect: effect.name,
        family: effect.family,
        action: effect.action,
        step: step.name,
      }));
    }
  }
}

function invalidEffectContractArgument(effect, contract) {
  for (const argument of contract.arguments) {
    const source = argument.aliases.find((alias) => Object.hasOwn(effect.args ?? {}, alias));
    if (!source) {
      continue;
    }
    const kind = effect.argKinds?.[source] ?? null;
    if (kind === "string" || kind === "identifier") {
      continue;
    }
    return {
      argument: argument.key,
      key: source,
      value: stringifyDiagnosticValue(effect.args[source]),
      kind: kind ?? "unknown",
    };
  }
  return null;
}

function stringifyDiagnosticValue(value) {
  if (Array.isArray(value)) {
    return JSON.stringify(value);
  }
  return String(value);
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
    const contract = effectContractForAccess(access);
    const argumentDiagnostic = contract ? invalidEffectContractArgument(access, contract) : null;
    if (argumentDiagnostic) {
      diagnostics.push(error("INTENT_CONTEXT_ARGUMENT_INVALID", `context '${context.expression}' argument '${argumentDiagnostic.argument}' must be a string for v0 contract '${contract.id}'.`, effectArgumentSpan(access, argumentDiagnostic), {
        context: context.expression,
        source: context.source,
        family: access.family,
        action: access.action,
        argument: argumentDiagnostic.argument,
        value: argumentDiagnostic.value,
        kind: argumentDiagnostic.kind,
        contractId: contract.id,
      }));
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
    if (!item.kind.startsWith("Raw")) {
      continue;
    }
    const blockName = unsupportedSyntaxBlockName(item.kind);
    diagnostics.push(error("INTENT_UNSUPPORTED_SYNTAX", `unsupported ${blockName} statement '${item.value}'.`, item.span, {
      syntax: item.value,
      goal: goal.name,
      block: blockName,
    }));
  }
}

function unsupportedSyntaxBlockName(kind) {
  if (kind === "RawPlanStatement") return "plan";
  if (kind === "RawStepStatement") return "step";
  if (kind === "RawVerifyStatement") return "verify";
  if (kind === "RawInvariantStatement") return "invariant";
  return "goal";
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

function validateMemoryAccesses(goal, diagnostics) {
  const memoryDeclarations = memoryDeclarationsByReference(goal);
  for (const step of goal.steps) {
    for (const access of step.memoryAccesses) {
      const declaration = memoryDeclarations.get(access.memory);
      if (!declaration) {
        diagnostics.push(error("INTENT_MEMORY_UNDECLARED", `step '${step.name}' references undeclared memory '${access.memory}'.`, access.span, {
          step: step.name,
          memory: access.memory,
          access: access.access,
          target: access.target,
        }));
        continue;
      }
      if (!access.key) {
        continue;
      }
      const declaredKeys = memoryDeclaredKeys(declaration.memory);
      if (declaredKeys.has(access.key)) {
        continue;
      }
      diagnostics.push(error("INTENT_MEMORY_KEY_UNDECLARED", `step '${step.name}' references undeclared memory key '${access.target}'.`, access.span, {
        step: step.name,
        memory: access.memory,
        key: access.key,
        access: access.access,
        target: access.target,
        declared_keys: [...declaredKeys.keys()],
      }));
    }
  }
}

function isSupportedRetentionUntil(value) {
  const normalized = value.trim();
  return normalized === "goal_complete"
    || normalized === "goal.completed"
    || /^[1-9][0-9]*(?:s|m|h|d)$/.test(normalized);
}

function memoryDeclarationsByReference(goal) {
  const declarations = new Map();
  for (const [index, memory] of goal.memory.entries()) {
    declarations.set(memory.scope, { memory, index });
    if (memory.name) {
      declarations.set(memory.name, { memory, index });
    }
  }
  return declarations;
}

function memoryRetentionSubjects(memory) {
  const subjects = new Map();
  for (const retention of memory.retentionRules ?? []) {
    if (retention.subject?.raw) {
      subjects.set(retention.subject.raw, retention);
    }
  }
  return subjects;
}

function memoryDeclaredKeys(memory) {
  const keys = memoryRetentionSubjects(memory);
  for (const key of memory.keys ?? []) {
    keys.set(key.name, key);
  }
  return keys;
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
    const impureEffect = verificationImpureEffect(requirement, goal.capabilities);
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

function validateCompletionProvenance(goal, diagnostics) {
  const provenance = completionProvenance(goal);
  if (!provenance.required) {
    return;
  }
  if (provenance.citations.length === 0) {
    const rule = provenance.requirements[0] ?? provenance.invariants[0] ?? null;
    diagnostics.push(error("INTENT_PROVENANCE_MISSING", `goal '${goal.name}' requires completion provenance but no memory citation is declared.`, rule?.span ?? goal.span, {
      goal: goal.name,
      requirements: provenance.requirements.map((requirement) => requirement.requirement),
      invariants: provenance.invariants.map((invariant) => invariant.invariant),
      citations: provenance.citations.length,
    }));
    return;
  }
  const unbackedCitations = unbackedCompletionCitations(goal);
  if (unbackedCitations.length === 0) {
    return;
  }
  const rule = provenance.requirements[0] ?? provenance.invariants[0] ?? null;
  diagnostics.push(error("INTENT_PROVENANCE_UNBACKED", `goal '${goal.name}' cites completion memory without an earlier write to the same target.`, unbackedCitations[0]?.span ?? rule?.span ?? goal.span, {
    goal: goal.name,
    requirements: provenance.requirements.map((requirement) => requirement.requirement),
    invariants: provenance.invariants.map((invariant) => invariant.invariant),
    citations: provenance.citations.length,
    unbacked_citations: unbackedCitations,
  }));
}

function completionProvenance(goal, citations = completionMemoryCitations(goal)) {
  const requirements = goal.verify
    .filter((requirement) => COMPLETION_PROVENANCE_REQUIREMENTS.has(requirement.value.trim()))
    .map((requirement) => ({
      requirement: requirement.value,
      span: requirement.span,
    }));
  const invariants = goal.invariants
    .filter((invariant) => invariant.kind === "Deny" && COMPLETION_PROVENANCE_INVARIANTS.has(invariant.value.trim()))
    .map((invariant) => ({
      assertion: invariant.kind,
      invariant: invariant.value,
      span: invariant.span,
    }));
  return {
    required: requirements.length > 0 || invariants.length > 0,
    requirements,
    invariants,
    citations,
  };
}

function completionMemoryCitations(goal) {
  const finalStep = goal.steps.at(-1);
  if (!finalStep) {
    return [];
  }
  return finalStep.memoryAccesses
    .filter((memoryAccess) => memoryAccess.access === "cite")
    .map((memoryAccess) => ({
      memory: memoryAccess.memory,
      key: memoryAccess.key,
      target: memoryAccess.target,
      step: finalStep.name,
      span: memoryAccess.span,
    }));
}

function unbackedCompletionCitations(goal) {
  const finalStep = goal.steps.at(-1);
  if (!finalStep) {
    return [];
  }
  const writes = [];
  const unbacked = [];
  for (const step of goal.steps) {
    for (const memoryAccess of step.memoryAccesses) {
      if (memoryAccess.access === "write") {
        writes.push({
          memory: memoryAccess.memory,
          key: memoryAccess.key,
          target: memoryAccess.target,
          step: step.name,
          span: memoryAccess.span,
        });
      }
      if (step !== finalStep || memoryAccess.access !== "cite") {
        continue;
      }
      const hasBackingWrite = writes.some((write) => {
        return write.memory === memoryAccess.memory
          && write.key === memoryAccess.key
          && write.target === memoryAccess.target
          && spanStartOffset(write.span) < spanStartOffset(memoryAccess.span);
      });
      if (!hasBackingWrite) {
        unbacked.push({
          memory: memoryAccess.memory,
          key: memoryAccess.key,
          target: memoryAccess.target,
          step: step.name,
          span: memoryAccess.span,
        });
      }
    }
  }
  return unbacked;
}

function validateCompletionCheckpoint(goal, diagnostics) {
  const checkpoint = completionCheckpoint(goal);
  if (!checkpoint.required || checkpoint.checkpoints.length > 0) {
    return;
  }
  const rule = checkpoint.requirements[0] ?? checkpoint.invariants[0] ?? null;
  diagnostics.push(error("INTENT_CHECKPOINT_MISSING", `goal '${goal.name}' requires a final-state checkpoint but the final step has none.`, rule?.span ?? goal.span, {
    goal: goal.name,
    step: goal.steps.at(-1)?.name ?? null,
    requirements: checkpoint.requirements.map((requirement) => requirement.requirement),
    invariants: checkpoint.invariants.map((invariant) => invariant.invariant),
    checkpoints: checkpoint.checkpoints.length,
  }));
}

function completionCheckpoint(goal, checkpoints = completionStepCheckpoints(goal)) {
  const requirements = goal.verify
    .filter((requirement) => COMPLETION_CHECKPOINT_REQUIREMENTS.has(requirement.value.trim()))
    .map((requirement) => ({
      requirement: requirement.value,
      span: requirement.span,
    }));
  const invariants = goal.invariants
    .filter((invariant) => invariant.kind === "Deny" && COMPLETION_CHECKPOINT_INVARIANTS.has(invariant.value.trim()))
    .map((invariant) => ({
      assertion: invariant.kind,
      invariant: invariant.value,
      span: invariant.span,
    }));
  return {
    required: requirements.length > 0 || invariants.length > 0,
    requirements,
    invariants,
    checkpoints,
  };
}

function requestEdgeData(step, effectUse) {
  return {
    name: effectUse.name,
    expression: effectUse.expression,
    family: effectUse.family,
    action: effectUse.action,
    contractId: effectContractId(effectUse),
    contractArguments: effectContractArgumentRefs(effectUse),
    args: effectUse.args,
    argKinds: effectUse.argKinds,
    argSpans: effectUse.argSpans,
    sourceSpan: step.span,
    targetSpan: effectUse.span,
  };
}

function contextInformsEdgeData(context, access, goal) {
  return {
    source: context.source,
    expression: context.expression,
    args: context.args,
    argKinds: context.argKinds,
    argSpans: context.argSpans,
    trust: context.trust,
    contractId: access?.contractId ?? null,
    contractArguments: access?.contractArguments ?? {},
    sourceSpan: context.span,
    targetSpan: goal.span,
  };
}

function stepPlanEdgeData(goal, step, index) {
  return {
    goal: goal.name,
    step: step.name,
    index,
    sourceSpan: goal.span,
    targetSpan: step.span,
  };
}

function stepPrecedesEdgeData(previousStep, nextStep, previousIndex, nextIndex) {
  return {
    previousStep: previousStep.name,
    nextStep: nextStep.name,
    previousIndex,
    nextIndex,
    sourceSpan: previousStep.span,
    targetSpan: nextStep.span,
  };
}

function typeDeclareEdgeData(typeDecl, goal) {
  return {
    type: typeDecl.name,
    definition: typeDecl.definition,
    goal: goal.name,
    sourceSpan: typeDecl.span,
    targetSpan: goal.span,
  };
}

function memoryDeclareEdgeData(goal, memory) {
  return {
    goal: goal.name,
    memory: memory.name ?? memory.scope,
    memoryScope: memory.scope,
    sourceSpan: goal.span,
    targetSpan: memory.span,
  };
}

function capabilityOwnerAuthorizationEdgeData(capability, goal) {
  return {
    capability: capability.name,
    family: capability.family,
    approvalPolicy: capabilityApprovalPolicy(capability),
    goal: goal.name,
    sourceSpan: capability.span,
    targetSpan: goal.span,
    ...(capability.action ? { action: capability.action } : {}),
  };
}

function completionStepCheckpoints(goal) {
  const finalStep = goal.steps.at(-1);
  if (!finalStep) {
    return [];
  }
  return finalStep.checkpoints.map((checkpoint) => ({
    checkpoint: checkpoint.value,
    step: finalStep.name,
    span: checkpoint.span,
  }));
}

function validateIrreversibleEffectCheckpoints(goal, diagnostics) {
  const invariant = goal.invariants.find((candidate) => {
    return candidate.kind === "Deny" && candidate.value.trim() === "uncheckpointed_irreversible_effect";
  });
  if (!invariant) {
    return;
  }
  for (const step of goal.steps) {
    for (const effect of step.effects) {
      if (!isIrreversibleEffect(effect)) {
        continue;
      }
      const checkpoints = checkpointsAfterEffect(goal, step, effect);
      if (checkpoints.length > 0) {
        continue;
      }
      diagnostics.push(error("INTENT_CHECKPOINT_MISSING", `effect '${effect.name}' is irreversible and must be followed by a checkpoint because invariant '${invariant.value}' is denied.`, effect.span, {
        goal: goal.name,
        step: step.name,
        invariant: invariant.value,
        effect: effect.name,
        family: effect.family,
        action: effect.action,
        contract_id: effectContractId(effect),
        effect_span: effect.span,
        invariant_span: invariant.span,
        checkpoint_coverage: "source_order_after_effect",
        checkpoints_after_effect: checkpoints.length,
      }));
    }
  }
}

function checkpointsAfterEffect(goal, step, effect) {
  const events = orderedCheckpointEvents(goal);
  const effectPosition = eventPosition(goal, step, effect);
  return events.filter((event) => {
    return event.kind === "checkpoint"
      && isEventAfter(event, effectPosition)
      && event.value.value.trim() !== "";
  });
}

function orderedCheckpointEvents(goal) {
  return goal.steps
    .flatMap((step, stepIndex) => {
      return [
        ...step.effects.map((effect) => ({ kind: "effect", value: effect, step, stepIndex, span: effect.span })),
        ...step.checkpoints.map((checkpoint) => ({ kind: "checkpoint", value: checkpoint, step, stepIndex, span: checkpoint.span })),
      ];
    })
    .sort(compareEvents);
}

function eventPosition(goal, step, value) {
  return {
    step,
    stepIndex: goal.steps.indexOf(step),
    span: value.span,
  };
}

function compareEvents(left, right) {
  if (left.stepIndex !== right.stepIndex) {
    return left.stepIndex - right.stepIndex;
  }
  return spanStartOffset(left.span) - spanStartOffset(right.span);
}

function isEventAfter(candidate, reference) {
  if (candidate.stepIndex !== reference.stepIndex) {
    return candidate.stepIndex > reference.stepIndex;
  }
  return spanStartsAfter(candidate.span, reference.span);
}

function isIrreversibleEffect(effect) {
  const contract = effectContractForAccess(effect);
  return contract?.risk === "irreversible"
    && contract.checkpoint.requiredWhen.includes("deny:uncheckpointed_irreversible_effect");
}

function spanStartOffset(value) {
  return value?.start?.offset ?? ((value?.start?.line ?? 0) * 100000 + (value?.start?.column ?? 0));
}

function spanStartsAfter(candidate, reference) {
  if (candidate?.start?.offset !== undefined && reference?.end?.offset !== undefined) {
    return candidate.start.offset > reference.end.offset;
  }
  if (candidate?.start?.line !== reference?.end?.line) {
    return candidate?.start?.line > reference?.end?.line;
  }
  return candidate?.start?.column > reference?.end?.column;
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
      edges.push(edge(typeId, goalId, "declares", typeDeclareEdgeData(typeDecl, goal)));
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
      edges.push(edge(inputId, goalId, "supplies", {
        parameter: parameter.name,
        type: normalizeTypeRef(parameter.type),
        sourceSpan: parameter.span,
        targetSpan: parameter.span,
      }));
      addProducer(producersByType, parameter.type, inputId, parameter.span);
    }

    for (const [index, context] of goal.context.entries()) {
      const id = `${goalId}:context:${index}`;
      const access = contextContractAccess(context);
      nodes.push(node(id, "Context", context.value, context.span, {
        source: context.source,
        args: context.args,
        argKinds: context.argKinds,
        argSpans: context.argSpans,
        expression: context.expression,
        trust: context.trust,
        ...(access?.contractId ? {
          contractId: access.contractId,
          contractArguments: access.contractArguments,
        } : {}),
      }));
      edges.push(edge(id, goalId, "informs", contextInformsEdgeData(context, access, goal)));
      if (access) {
        for (const [capabilityIndex, capability] of goal.capabilities.entries()) {
          if (isFamilyMatch(access.family, capability.family) && !getCapabilityDenial(access, [capability])) {
            edges.push(edge(`${goalId}:capability:${capabilityIndex}`, id, "authorizes", authorizationEdgeData(access, capability)));
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
        approvalPolicy: capabilityApprovalPolicy(capability),
      }));
      edges.push(edge(id, goalId, "authorizes", capabilityOwnerAuthorizationEdgeData(capability, goal)));
    }

    const memoryIdsByReference = new Map();
    const completionCitations = [];
    for (const [index, memory] of goal.memory.entries()) {
      const id = `${goalId}:memory:${index}`;
      nodes.push(node(id, "Memory", memory.name ?? memory.scope, memory.span, {
        scope: memory.scope,
        retention: memory.retention,
        retentionRules: memory.retentionRules ?? [],
        keys: memory.keys ?? [],
      }));
      edges.push(edge(goalId, id, "declares", memoryDeclareEdgeData(goal, memory)));
      memoryIdsByReference.set(memory.scope, { id, span: memory.span, memory });
      if (memory.name) {
        memoryIdsByReference.set(memory.name, { id, span: memory.span, memory });
      }
    }

    let previousStep = null;
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
        memoryAccesses: step.memoryAccesses.map((access) => access.target),
      }));
      edges.push(edge(goalId, id, "plans", stepPlanEdgeData(goal, step, index)));
      if (previousStepId && previousStep) {
        edges.push(edge(previousStepId, id, "precedes", stepPrecedesEdgeData(previousStep, step, index - 1, index)));
      }
      previousStep = step;
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
        edges.push(edge(requirementId, goalId, "gates", {
          requirement: requirement.value,
          scope: "step",
          sourceSpan: requirement.span,
          targetSpan: goal.span,
        }));
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

      for (const memoryAccess of step.memoryAccesses) {
        const memory = memoryIdsByReference.get(memoryAccess.memory);
        if (!memory) {
          continue;
        }
        const retention = memoryAccess.key ? memoryRetentionSubjects(memory.memory).get(memoryAccess.key) : null;
        const declaredKey = memoryAccess.key ? memoryDeclaredKeys(memory.memory).get(memoryAccess.key) : null;
        const payload = {
          access: memoryAccess.access,
          memory: memoryAccess.memory,
          key: memoryAccess.key,
          target: memoryAccess.target,
          retentionRef: retention?.raw ?? null,
          sourceSpan: memoryAccess.access === "write" ? memoryAccess.span : memory.span,
          targetSpan: memoryAccess.access === "write" ? (declaredKey?.span ?? memory.span) : memoryAccess.span,
        };
        if (memoryAccess.access === "cite") {
          completionCitations.push({
            memory: memoryAccess.memory,
            key: memoryAccess.key,
            target: memoryAccess.target,
            step: step.name,
            span: memoryAccess.span,
          });
        }
        if (memoryAccess.access === "write") {
          edges.push(edge(id, memory.id, "writes", payload));
        } else {
          edges.push(edge(memory.id, id, memoryAccess.access === "cite" ? "cites" : "reads", payload));
        }
      }

      for (const [effectIndex, effectUse] of step.effects.entries()) {
        const effectId = `${id}:effect:${effectIndex}`;
        const approvalRequired = Boolean(approvalRequiredCapability(effectUse, goal.capabilities));
        nodes.push(node(effectId, "Effect", effectUse.name, effectUse.span, {
          family: effectUse.family,
          action: effectUse.action,
          contractId: effectContractId(effectUse),
          contractArguments: effectContractArgumentRefs(effectUse),
          args: effectUse.args,
          argKinds: effectUse.argKinds,
          argSpans: effectUse.argSpans,
          trust: effectTrust(effectUse),
          expression: effectUse.expression,
          approvalRequired,
        }));
        edges.push(edge(id, effectId, "requests", requestEdgeData(step, effectUse)));
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
            edges.push(edge(`${goalId}:capability:${capabilityIndex}`, effectId, "authorizes", authorizationEdgeData(effectUse, capability)));
          }
        }
      }

      addProducer(producersByType, step.outputType, id, step.outputTypeSpan ?? step.span);
    }

    const completionId = `${goalId}:completion`;
    const finalStep = goal.steps.at(-1);
    const provenance = completionProvenance(goal, completionCitations.filter((citation) => citation.step === finalStep?.name));
    const checkpoint = completionCheckpoint(goal);
    nodes.push(node(completionId, "Completion", goal.name, goal.span, {
      outputType: goal.outputType,
      outputTypeSpan: goal.outputTypeSpan,
      provenance,
      checkpoint,
    }));
    edges.push(edge(goalId, completionId, "completes"));
    if (lastStepId) {
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
        scope: "goal",
        effect: {
          family: effect.family,
          action: effect.action,
          contractId: effectContractId(effect),
          contractArguments: effectContractArgumentRefs(effect),
          args: effect.args,
          argKinds: effect.argKinds,
          argSpans: effect.argSpans,
          trust: effectTrust(effect),
        },
      } : {
        requirement: check.value,
        scope: "goal",
      }));
      edges.push(edge(id, goalId, "gates", {
        requirement: check.value,
        scope: "goal",
        sourceSpan: check.span,
        targetSpan: goal.span,
      }));
      edges.push(edge(id, completionId, "verifies", {
        requirement: check.value,
        scope: "goal",
        sourceSpan: check.span,
        targetSpan: goal.span,
      }));
      if (effect) {
        for (const [capabilityIndex, capability] of goal.capabilities.entries()) {
          if (isFamilyMatch(effect.family, capability.family) && !getCapabilityDenial(effect, [capability])) {
            edges.push(edge(`${goalId}:capability:${capabilityIndex}`, id, "authorizes", authorizationEdgeData(effect, capability)));
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
  const graphNodes = [];
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
    graphNodes.push(graphNode);
  }
  const fallbackSpan = graph.nodes[0]?.span ?? graphSpan;
  const outgoing = new Map([...nodesById.keys()].map((nodeId) => [nodeId, []]));
  const incomingEdgesByNode = new Map([...nodesById.keys()].map((nodeId) => [nodeId, []]));
  const outgoingEdgesByNode = new Map([...nodesById.keys()].map((nodeId) => [nodeId, []]));
  const incomingDataCounts = new Map();
  const incomingCompletionEdges = new Map();
  const incomingAuthorizationEdges = new Map();
  const guardTargetsByInvariant = new Map();
  const graphEdges = [];

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
    const typedEdgeDiagnostic = validateGraphTypedEdgeContract(nodesById, graphEdge, fallbackSpan);
    if (typedEdgeDiagnostic) {
      diagnostics.push(typedEdgeDiagnostic);
      continue;
    }
    const memoryTargetDiagnostic = validateGraphMemoryTarget(nodesById, graphEdge, fallbackSpan);
    if (memoryTargetDiagnostic) {
      diagnostics.push(memoryTargetDiagnostic);
      continue;
    }
    graphEdges.push(graphEdge);
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

  for (const graphNode of graphNodes) {
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
      const approvalRequiredEffectIds = graphNodes
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

  for (const graphNode of graphNodes) {
    if (graphNode.kind !== "Step") {
      continue;
    }
    diagnostics.push(...validateGraphStepMetadata(nodesById, incomingEdgesByNode, outgoingEdgesByNode, graphNode, fallbackSpan));
  }

  for (const graphNode of graphNodes) {
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
      continue;
    }
    const requestMetadataDiagnostic = validateGraphEffectRequestMetadata(ownerStepRequestEdges[0], ownerStep, graphNode, fallbackSpan);
    if (requestMetadataDiagnostic) {
      diagnostics.push(requestMetadataDiagnostic);
    }
  }

  for (const graphNode of graphNodes) {
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
    const invalidGrantAuthorizations = capabilityAuthorizationEdges
      .map((graphEdge) => invalidGraphGrantAuthorization(nodesById.get(graphEdge.from), graphNode, graphEdge))
      .filter(Boolean);
    if (invalidGrantAuthorizations.length > 0) {
      diagnostics.push(error("INTENT_GRAPH_AUTHORIZATION_GRANT_INVALID", `${graphNode.kind} '${graphNode.label}' must be authorized by matching Capability grants.`, graphNode.span ?? fallbackSpan, {
        target: graphNode.label,
        target_id: graphNode.id,
        target_kind: graphNode.kind,
        invalid_authorizations: invalidGrantAuthorizations,
      }));
    }
  }

  for (const graphNode of graphNodes) {
    if (graphNode.kind !== "Capability") {
      continue;
    }
    const ownershipDiagnostic = validateGraphCapabilityAuthorization(nodesById, outgoingEdgesByNode, graphNode, fallbackSpan);
    if (ownershipDiagnostic) {
      diagnostics.push(ownershipDiagnostic);
    }
  }

  for (const graphNode of graphNodes) {
    if (graphNode.kind !== "Context") {
      continue;
    }
    const informsDiagnostic = validateGraphContextInforms(nodesById, outgoingEdgesByNode, graphNode, fallbackSpan);
    if (informsDiagnostic) {
      diagnostics.push(informsDiagnostic);
    }
  }

  for (const graphNode of graphNodes) {
    if (graphNode.kind !== "Memory") {
      continue;
    }
    const declareDiagnostic = validateGraphMemoryDeclare(nodesById, incomingEdgesByNode, graphNode, fallbackSpan);
    if (declareDiagnostic) {
      diagnostics.push(declareDiagnostic);
    }
  }

  for (const graphNode of graphNodes) {
    if (graphNode.kind !== "Type") {
      continue;
    }
    const declareDiagnostic = validateGraphTypeDeclarations(nodesById, outgoingEdgesByNode, graphNode, fallbackSpan);
    if (declareDiagnostic) {
      diagnostics.push(declareDiagnostic);
    }
  }

  for (const graphNode of graphNodes) {
    if (graphNode.kind !== "Completion") {
      continue;
    }
    const incomingEdges = incomingCompletionEdges.get(graphNode.id) ?? [];
    const completingEdges = incomingEdges.filter((graphEdge) => graphEdge.kind === "completes" && nodesById.get(graphEdge.from)?.kind === "Goal");
    const producingEdges = incomingEdges.filter((graphEdge) => graphEdge.kind === "produces" && nodesById.get(graphEdge.from)?.kind === "Step");
    const verifyingEdges = incomingEdges.filter((graphEdge) => graphEdge.kind === "verifies" && nodesById.get(graphEdge.from)?.kind === "Check");
    const guardingEdges = incomingEdges.filter((graphEdge) => graphEdge.kind === "guards" && nodesById.get(graphEdge.from)?.kind === "Invariant");
    const citationEdges = producingEdges.flatMap((graphEdge) => {
      return (incomingEdgesByNode.get(graphEdge.from) ?? [])
        .filter((candidate) => candidate.kind === "cites" && nodesById.get(candidate.from)?.kind === "Memory");
    });
    const checkpointEdges = producingEdges.flatMap((graphEdge) => {
      return (outgoingEdgesByNode.get(graphEdge.from) ?? [])
        .filter((candidate) => candidate.kind === "checkpoints" && nodesById.get(candidate.to)?.kind === "Checkpoint");
    });
    const goalId = graphNode.id.endsWith(":completion") ? graphNode.id.slice(0, -":completion".length) : null;
    const expectedGuardEdges = goalId
      ? graphNodes.filter((candidate) => candidate.kind === "Invariant" && candidate.id.startsWith(`${goalId}:invariant:`)).length
      : guardingEdges.length;
    const provenanceRequired = graphNode.data?.provenance?.required === true;
    const hasRequiredCitationEdges = !provenanceRequired || citationEdges.length > 0;
    const checkpointRequired = graphNode.data?.checkpoint?.required === true;
    const hasRequiredCheckpointEdges = !checkpointRequired || checkpointEdges.length > 0;
    if (completingEdges.length !== 1 || producingEdges.length !== 1 || verifyingEdges.length < 1 || guardingEdges.length !== expectedGuardEdges || !hasRequiredCitationEdges || !hasRequiredCheckpointEdges) {
      diagnostics.push(error("INTENT_GRAPH_COMPLETION_INVALID", `completion '${graphNode.label}' must have incoming completes, produces, verifies, and invariant guard edges.`, graphNode.span ?? fallbackSpan, {
        completion: graphNode.label,
        completion_id: graphNode.id,
        completes_edges: completingEdges.length,
        produces_edges: producingEdges.length,
        verifies_edges: verifyingEdges.length,
        guards_edges: guardingEdges.length,
        expected_guard_edges: expectedGuardEdges,
        provenance_required: provenanceRequired,
        citation_edges: citationEdges.length,
        has_required_citation_edges: hasRequiredCitationEdges,
        checkpoint_required: checkpointRequired,
        checkpoint_edges: checkpointEdges.length,
        has_required_checkpoint_edges: hasRequiredCheckpointEdges,
      }));
    }
    for (const metadataDiagnostic of validateGraphCompletionMetadata(graphNode, producingEdges, citationEdges, checkpointEdges, graphEdges, nodesById, fallbackSpan)) {
      diagnostics.push(metadataDiagnostic);
    }
  }

  for (const graphNode of graphNodes) {
    if (graphNode.kind !== "Check") {
      continue;
    }
    const gateDiagnostic = validateGraphCheckGate(nodesById, outgoingEdgesByNode, graphNode, fallbackSpan);
    if (gateDiagnostic) {
      diagnostics.push(gateDiagnostic);
    }
  }

  for (const graphNode of graphNodes) {
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
    const missingGuardTargets = invariantGuardTargetIds(graphNodes, goalId).filter((targetId) => !guardedTargets.has(targetId));
    if (missingGuardTargets.length > 0) {
      diagnostics.push(error("INTENT_GRAPH_GUARD_INVALID", `invariant '${graphNode.label}' must guard completion and step-scoped effect, checkpoint, and requirement nodes.`, graphNode.span ?? fallbackSpan, {
        invariant: graphNode.label,
        invariant_id: graphNode.id,
        missing_guard_targets: missingGuardTargets,
      }));
    }
  }

  for (const graphNode of graphNodes) {
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

  for (const graphNode of graphNodes) {
    if (graphNode.kind !== "Input" || graphNode.data?.scope !== "goal") {
      continue;
    }
    const supplyDiagnostic = validateGraphInputSupply(nodesById, outgoingEdgesByNode, graphNode, fallbackSpan);
    if (supplyDiagnostic) {
      diagnostics.push(supplyDiagnostic);
    }
  }

  for (const graphNode of graphNodes) {
    if (graphNode.kind !== "Step") {
      continue;
    }
    const ownerGoalId = parentNodeId(graphNode.id, ":step:");
    const ownerGoal = ownerGoalId ? nodesById.get(ownerGoalId) : null;
    const planEdges = (incomingEdgesByNode.get(graphNode.id) ?? []).filter((graphEdge) => graphEdge.kind === "plans");
    const ownerPlanEdges = planEdges.filter((graphEdge) => graphEdge.from === ownerGoalId && ownerGoal?.kind === "Goal");
    if (ownerPlanEdges.length === 1 && planEdges.length === ownerPlanEdges.length) {
      const planMetadataDiagnostic = validateGraphStepPlanMetadata(ownerPlanEdges[0], ownerGoal, graphNode, graphStepIndex(graphNodes, ownerGoalId, graphNode.id), fallbackSpan);
      if (planMetadataDiagnostic) {
        diagnostics.push(planMetadataDiagnostic);
      }
      continue;
    }
    {
      diagnostics.push(error("INTENT_GRAPH_STEP_PLAN_INVALID", `step '${graphNode.label}' must have exactly one incoming plans edge from its owning goal.`, graphNode.span ?? fallbackSpan, {
        step: graphNode.label,
        step_id: graphNode.id,
        owner_goal_id: ownerGoalId,
        plans_edges: planEdges.length,
        owner_goal_plans_edges: ownerPlanEdges.length,
      }));
    }
  }

  for (const graphNode of graphNodes) {
    if (graphNode.kind !== "Goal") {
      continue;
    }
    const sequenceDiagnostic = validateGoalStepSequence(graphNodes, graphEdges, incomingEdgesByNode, graphNode, fallbackSpan);
    if (sequenceDiagnostic) {
      diagnostics.push(sequenceDiagnostic);
    }
  }

  for (const graphNode of graphNodes) {
    if (graphNode.kind !== "Goal") {
      continue;
    }
    diagnostics.push(...validateGraphGoalMetadata(nodesById, incomingEdgesByNode, graphNode, fallbackSpan));
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
  const invalidDeclareMetadata = [];
  for (const graphEdge of declareEdges) {
    if (!goalIdSet.has(graphEdge.to)) {
      invalidTargetIds.push(graphEdge.to);
      continue;
    }
    const goalNode = nodesById.get(graphEdge.to);
    const metadata = validateGraphTypeDeclareMetadata(graphEdge, graphNode, goalNode);
    if (!typeDeclareMetadataIsValid(metadata)) {
      invalidDeclareMetadata.push(metadata);
    }
    declaredGoalCounts.set(graphEdge.to, (declaredGoalCounts.get(graphEdge.to) ?? 0) + 1);
  }
  const missingGoalIds = goalIds.filter((goalId) => !declaredGoalCounts.has(goalId));
  const duplicateGoalIds = goalIds.filter((goalId) => (declaredGoalCounts.get(goalId) ?? 0) > 1);
  if (missingGoalIds.length === 0 && duplicateGoalIds.length === 0 && invalidTargetIds.length === 0 && invalidDeclareMetadata.length === 0) {
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
    invalid_declare_metadata: invalidDeclareMetadata,
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
  const outputTypeSpanIsValid = isGraphOutputTypeSpanValid(graphNode.data.outputType, graphNode.data.outputTypeSpan);
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

function validateGraphGoalMetadata(nodesById, incomingEdgesByNode, graphNode, fallbackSpan) {
  return [
    validateGraphGoalParameterMetadata(nodesById, incomingEdgesByNode, graphNode, fallbackSpan),
    validateGraphGoalCompletionMetadata(nodesById, graphNode, fallbackSpan),
  ].filter((diagnostic) => diagnostic !== null);
}

function validateGraphGoalParameterMetadata(nodesById, incomingEdgesByNode, graphNode, fallbackSpan) {
  const declaredParameters = graphNode.data?.parameters;
  const ownedInputs = ownedIncomingNodes(nodesById, incomingEdgesByNode, graphNode.id, "supplies", "Input")
    .filter((ownedNode) => ownedNode.data?.scope === "goal");
  if (!Array.isArray(declaredParameters) || declaredParameters.some((parameter) => !isGraphParameterRecord(parameter)) || (declaredParameters.length === 0 && ownedInputs.length === 0)) {
    return null;
  }
  const ownedValues = ownedInputs.map((ownedNode) => ({
    name: ownedNode.label,
    type: ownedNode.data?.type,
    span: ownedNode.span,
  }));
  if (parameterArraysEqual(declaredParameters, ownedValues)) {
    return null;
  }
  return error("INTENT_GRAPH_GOAL_METADATA_INVALID", `goal '${graphNode.label}' parameter metadata must match owned goal input nodes in source order.`, graphNode.span ?? fallbackSpan, {
    goal: graphNode.label,
    goal_id: graphNode.id,
    field: "parameters",
    declared_values: declaredParameters,
    owned_values: ownedValues,
    owned_node_ids: ownedInputs.map((ownedNode) => ownedNode.id),
    declared_count: declaredParameters.length,
    owned_count: ownedInputs.length,
    mismatched_indexes: mismatchedParameterIndexes(declaredParameters, ownedValues),
  });
}

function validateGraphGoalCompletionMetadata(nodesById, graphNode, fallbackSpan) {
  const completionNode = nodesById.get(`${graphNode.id}:completion`);
  if (completionNode?.kind !== "Completion" || !isGraphOutputMetadataValid(graphNode.data) || !isGraphOutputMetadataValid(completionNode.data)) {
    return null;
  }
  const declaredValue = graphOutputMetadata(graphNode);
  const ownedValue = graphOutputMetadata(completionNode);
  if (outputMetadataEqual(declaredValue, ownedValue)) {
    return null;
  }
  return error("INTENT_GRAPH_GOAL_METADATA_INVALID", `goal '${graphNode.label}' output metadata must match its completion node.`, graphNode.span ?? fallbackSpan, {
    goal: graphNode.label,
    goal_id: graphNode.id,
    field: "outputType",
    declared_value: declaredValue,
    owned_value: ownedValue,
    owned_node_ids: [completionNode.id],
  });
}

function isGraphOutputMetadataValid(data) {
  return data?.outputType === null
    ? data.outputTypeSpan === null
    : typeof data?.outputType === "string" && data.outputType.trim() !== "" && isSpan(data.outputTypeSpan);
}

function graphOutputMetadata(graphNode) {
  return {
    outputType: graphNode.data.outputType,
    outputTypeSpan: graphNode.data.outputTypeSpan,
  };
}

function outputMetadataEqual(left, right) {
  return left?.outputType === right?.outputType && outputSpansEqual(left?.outputTypeSpan, right?.outputTypeSpan);
}

function outputSpansEqual(left, right) {
  return left === null && right === null ? true : spansEqual(left, right);
}

function validateGraphCompletionMetadata(graphNode, producingEdges, citationEdges, checkpointEdges, graphEdges, nodesById, fallbackSpan) {
  if (producingEdges.length !== 1 || nodesById.get(producingEdges[0].from)?.kind !== "Step") {
    return [];
  }
  const producingEdge = producingEdges[0];
  return [
    validateGraphCompletionCitationMetadata(graphNode, producingEdge, citationEdges, nodesById, fallbackSpan),
    validateGraphCompletionCitationBacking(graphNode, citationEdges, graphEdges, fallbackSpan),
    validateGraphCompletionCheckpointMetadata(graphNode, producingEdge, checkpointEdges, nodesById, fallbackSpan),
  ].filter((diagnostic) => diagnostic !== null);
}

function validateGraphCompletionCitationMetadata(graphNode, producingEdge, citationEdges, nodesById, fallbackSpan) {
  if (!isGraphCompletionProvenanceValid(graphNode.data?.provenance)) {
    return null;
  }
  const declaredValues = graphNode.data.provenance.citations;
  const edgeValues = citationEdges.map((graphEdge) => {
    const stepNode = nodesById.get(producingEdge.from);
    return {
      memory: graphEdge.data.memory,
      key: graphEdge.data.key ?? null,
      target: graphEdge.data.target,
      step: stepNode?.label ?? null,
      span: graphEdge.data.targetSpan,
    };
  });
  if (provenanceCitationArraysEqual(declaredValues, edgeValues)) {
    return null;
  }
  return completionMetadataError(graphNode, fallbackSpan, "provenance.citations", declaredValues, edgeValues, citationEdges);
}

function validateGraphCompletionCitationBacking(graphNode, citationEdges, graphEdges, fallbackSpan) {
  if (!isGraphCompletionProvenanceValid(graphNode.data?.provenance) || graphNode.data.provenance.required !== true) {
    return null;
  }
  const writeEdges = graphEdges.filter((graphEdge) => graphEdge.kind === "writes");
  const unbackedCitations = citationEdges
    .filter((citationEdge) => !writeEdges.some((writeEdge) => {
      return writeEdge.to === citationEdge.from
        && writeEdge.data?.memory === citationEdge.data?.memory
        && (writeEdge.data?.key ?? null) === (citationEdge.data?.key ?? null)
        && writeEdge.data?.target === citationEdge.data?.target
        && spanStartOffset(writeEdge.data?.sourceSpan) < spanStartOffset(citationEdge.data?.targetSpan);
    }))
    .map((citationEdge) => ({
      from: citationEdge.from,
      to: citationEdge.to,
      memory: citationEdge.data?.memory ?? null,
      key: citationEdge.data?.key ?? null,
      target: citationEdge.data?.target ?? null,
    }));
  if (unbackedCitations.length === 0) {
    return null;
  }
  return error("INTENT_GRAPH_COMPLETION_METADATA_INVALID", `completion '${graphNode.label}' provenance citations must be backed by earlier writes to the same memory target.`, graphNode.span ?? fallbackSpan, {
    completion: graphNode.label,
    completion_id: graphNode.id,
    field: "provenance.citation_backing",
    unbacked_citations: unbackedCitations,
    write_edges: writeEdges.map((writeEdge) => ({
      from: writeEdge.from,
      to: writeEdge.to,
      memory: writeEdge.data?.memory ?? null,
      key: writeEdge.data?.key ?? null,
      target: writeEdge.data?.target ?? null,
    })),
  });
}

function validateGraphCompletionCheckpointMetadata(graphNode, producingEdge, checkpointEdges, nodesById, fallbackSpan) {
  if (!isGraphCompletionCheckpointValid(graphNode.data?.checkpoint)) {
    return null;
  }
  const declaredValues = graphNode.data.checkpoint.checkpoints;
  const stepNode = nodesById.get(producingEdge.from);
  const edgeValues = checkpointEdges.map((graphEdge) => {
    const checkpointNode = nodesById.get(graphEdge.to);
    return {
      checkpoint: checkpointNode?.data?.checkpoint ?? graphEdge.data?.checkpoint ?? null,
      step: stepNode?.label ?? null,
      span: checkpointNode?.span ?? null,
    };
  });
  if (completionCheckpointArraysEqual(declaredValues, edgeValues)) {
    return null;
  }
  return completionMetadataError(graphNode, fallbackSpan, "checkpoint.checkpoints", declaredValues, edgeValues, checkpointEdges);
}

function completionMetadataError(graphNode, fallbackSpan, field, declaredValues, edgeValues, graphEdges) {
  return error("INTENT_GRAPH_COMPLETION_METADATA_INVALID", `completion '${graphNode.label}' metadata field '${field}' must match final step graph edges in source order.`, graphNode.span ?? fallbackSpan, {
    completion: graphNode.label,
    completion_id: graphNode.id,
    field,
    declared_values: declaredValues,
    edge_values: edgeValues,
    edge_ids: graphEdges.map((graphEdge) => ({ from: graphEdge.from, to: graphEdge.to, kind: graphEdge.kind })),
    declared_count: declaredValues.length,
    edge_count: edgeValues.length,
    mismatched_indexes: mismatchedRecordIndexes(declaredValues, edgeValues, field === "provenance.citations" ? provenanceCitationsEqual : completionCheckpointsEqual),
  });
}

function provenanceCitationArraysEqual(left, right) {
  return recordArraysEqual(left, right, provenanceCitationsEqual);
}

function provenanceCitationsEqual(left, right) {
  return left?.memory === right?.memory
    && (left?.key ?? null) === (right?.key ?? null)
    && left?.target === right?.target
    && left?.step === right?.step
    && spansEqual(left?.span, right?.span);
}

function completionCheckpointArraysEqual(left, right) {
  return recordArraysEqual(left, right, completionCheckpointsEqual);
}

function completionCheckpointsEqual(left, right) {
  return left?.checkpoint === right?.checkpoint
    && left?.step === right?.step
    && spansEqual(left?.span, right?.span);
}

function recordArraysEqual(left, right, equals) {
  return Array.isArray(left)
    && Array.isArray(right)
    && left.length === right.length
    && left.every((value, index) => equals(value, right[index]));
}

function mismatchedRecordIndexes(left, right, equals) {
  return Array.from({ length: Math.max(left.length, right.length) }, (_, index) => index)
    .filter((index) => !equals(left[index], right[index]));
}

function validateGraphCompletion(graphNode, graphSpan) {
  if (graphNode.kind !== "Completion") {
    return null;
  }
  const outputTypeIsValid = graphNode.data.outputType === null
    || (typeof graphNode.data.outputType === "string" && graphNode.data.outputType.trim() !== "");
  const outputTypeSpanIsValid = isGraphOutputTypeSpanValid(graphNode.data.outputType, graphNode.data.outputTypeSpan);
  const provenanceDiagnostic = validateGraphCompletionProvenance(graphNode.data.provenance);
  const checkpointDiagnostic = validateGraphCompletionCheckpoint(graphNode.data.checkpoint);
  if (outputTypeIsValid && outputTypeSpanIsValid && !provenanceDiagnostic && !checkpointDiagnostic) {
    return null;
  }
  return error("INTENT_GRAPH_COMPLETION_INVALID", `completion '${graphNode.label}' must carry valid output contract data.`, graphNode.span ?? graphSpan, {
    completion: graphNode.label,
    completion_id: graphNode.id,
    output_type_is_valid: outputTypeIsValid,
    output_type_span_is_valid: outputTypeSpanIsValid,
    provenance_is_valid: provenanceDiagnostic ? provenanceDiagnostic.provenance_is_valid : true,
    provenance_required: provenanceDiagnostic ? provenanceDiagnostic.provenance_required : Boolean(graphNode.data.provenance?.required),
    provenance_citations: Array.isArray(graphNode.data.provenance?.citations) ? graphNode.data.provenance.citations.length : null,
    provenance_has_required_citations: provenanceDiagnostic ? provenanceDiagnostic.provenance_has_required_citations : true,
    checkpoint_is_valid: checkpointDiagnostic ? checkpointDiagnostic.checkpoint_is_valid : true,
    checkpoint_required: checkpointDiagnostic ? checkpointDiagnostic.checkpoint_required : Boolean(graphNode.data.checkpoint?.required),
    completion_checkpoints: Array.isArray(graphNode.data.checkpoint?.checkpoints) ? graphNode.data.checkpoint.checkpoints.length : null,
    checkpoint_has_required_records: checkpointDiagnostic ? checkpointDiagnostic.checkpoint_has_required_records : true,
  });
}

function validateGraphCompletionProvenance(provenance) {
  const provenanceIsValid = isGraphCompletionProvenanceValid(provenance);
  const provenanceHasRequiredCitations = provenanceIsValid
    && (!provenance.required || provenance.citations.length > 0);
  if (provenanceIsValid && provenanceHasRequiredCitations) {
    return null;
  }
  return {
    provenance_is_valid: provenanceIsValid,
    provenance_required: isPlainObject(provenance) && typeof provenance.required === "boolean" ? provenance.required : null,
    provenance_has_required_citations: provenanceHasRequiredCitations,
  };
}

function isGraphCompletionProvenanceValid(provenance) {
  return isPlainObject(provenance)
    && typeof provenance.required === "boolean"
    && Array.isArray(provenance.requirements)
    && provenance.requirements.every(isGraphProvenanceRequirement)
    && Array.isArray(provenance.invariants)
    && provenance.invariants.every(isGraphProvenanceInvariant)
    && Array.isArray(provenance.citations)
    && provenance.citations.every(isGraphProvenanceCitation);
}

function isGraphProvenanceRequirement(value) {
  return isPlainObject(value)
    && typeof value.requirement === "string"
    && value.requirement.trim() !== ""
    && isSpan(value.span);
}

function isGraphProvenanceInvariant(value) {
  return isPlainObject(value)
    && (value.assertion === "Require" || value.assertion === "Deny")
    && typeof value.invariant === "string"
    && value.invariant.trim() !== ""
    && isSpan(value.span);
}

function isGraphProvenanceCitation(value) {
  return isPlainObject(value)
    && typeof value.memory === "string"
    && value.memory.trim() !== ""
    && (value.key === null || (typeof value.key === "string" && value.key.trim() !== ""))
    && typeof value.target === "string"
    && value.target.trim() !== ""
    && typeof value.step === "string"
    && value.step.trim() !== ""
    && isSpan(value.span);
}

function validateGraphCompletionCheckpoint(checkpoint) {
  const checkpointIsValid = isGraphCompletionCheckpointValid(checkpoint);
  const checkpointHasRequiredRecords = checkpointIsValid
    && (!checkpoint.required || checkpoint.checkpoints.length > 0);
  if (checkpointIsValid && checkpointHasRequiredRecords) {
    return null;
  }
  return {
    checkpoint_is_valid: checkpointIsValid,
    checkpoint_required: isPlainObject(checkpoint) && typeof checkpoint.required === "boolean" ? checkpoint.required : null,
    checkpoint_has_required_records: checkpointHasRequiredRecords,
  };
}

function isGraphCompletionCheckpointValid(checkpoint) {
  return isPlainObject(checkpoint)
    && typeof checkpoint.required === "boolean"
    && Array.isArray(checkpoint.requirements)
    && checkpoint.requirements.every(isGraphCheckpointRequirement)
    && Array.isArray(checkpoint.invariants)
    && checkpoint.invariants.every(isGraphCheckpointInvariant)
    && Array.isArray(checkpoint.checkpoints)
    && checkpoint.checkpoints.every(isGraphCompletionCheckpointRecord);
}

function isGraphCheckpointRequirement(value) {
  return isPlainObject(value)
    && typeof value.requirement === "string"
    && value.requirement.trim() !== ""
    && isSpan(value.span);
}

function isGraphCheckpointInvariant(value) {
  return isPlainObject(value)
    && (value.assertion === "Require" || value.assertion === "Deny")
    && typeof value.invariant === "string"
    && value.invariant.trim() !== ""
    && isSpan(value.span);
}

function isGraphCompletionCheckpointRecord(value) {
  return isPlainObject(value)
    && typeof value.checkpoint === "string"
    && value.checkpoint.trim() !== ""
    && typeof value.step === "string"
    && value.step.trim() !== ""
    && isSpan(value.span);
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
  const invalidGrantIndexes = grantsIsArray
    ? graphNode.data.grants
        .map((grant, grantIndex) => isGraphGrantRecord(grant, graphNode.data.family) ? null : grantIndex)
        .filter((grantIndex) => grantIndex !== null)
    : [];
  const approvalPolicyIsValid = graphNode.data.approvalPolicy === "none" || graphNode.data.approvalPolicy === "required";
  if (familyIsNonempty && grantsIsArray && invalidGrantIndexes.length === 0 && approvalPolicyIsValid) {
    return null;
  }
  return error("INTENT_GRAPH_CAPABILITY_INVALID", `capability '${graphNode.label}' must carry valid authorization policy data.`, graphNode.span ?? graphSpan, {
    capability: graphNode.label,
    capability_id: graphNode.id,
    family: typeof graphNode.data.family === "string" ? graphNode.data.family : null,
    approval_policy: typeof graphNode.data.approvalPolicy === "string" ? graphNode.data.approvalPolicy : null,
    family_is_nonempty: familyIsNonempty,
    grants_is_array: grantsIsArray,
    invalid_grant_indexes: invalidGrantIndexes,
    approval_policy_is_valid: approvalPolicyIsValid,
  });
}

function isGraphGrantRecord(value, family = null) {
  const baseIsValid = isPlainObject(value)
    && typeof value.action === "string"
    && value.action.trim() !== ""
    && typeof value.key === "string"
    && value.key.trim() !== ""
    && isGrantArgumentValue(value.value)
    && typeof value.raw === "string"
    && value.raw.trim() !== ""
    && isSpan(value.span)
    && isSpan(value.actionSpan)
    && typeof value.approvalRequired === "boolean"
    && Array.isArray(value.args)
    && value.args.length > 0
    && value.args.every(isGrantArgumentRecord)
    && value.args[0].key === value.key
    && grantValuesEqual(value.args[0].value, value.value);
  if (!baseIsValid) {
    return false;
  }
  if (value.contractId === undefined && value.contractArgument === undefined) {
    return true;
  }
  const contract = typeof value.contractId === "string" && value.contractId.trim() !== ""
    ? effectContractById(value.contractId)
    : null;
  return Boolean(contract)
    && typeof value.contractArgument === "string"
    && value.contractArgument.trim() !== ""
    && isFamilyMatch(contract.family, family)
    && contract.action === value.action
    && contract.arguments.some((argument) => argument.key === value.contractArgument && argument.key === value.key);
}

function isGrantArgumentRecord(value) {
  return isPlainObject(value)
    && typeof value.key === "string"
    && value.key.trim() !== ""
    && isGrantArgumentValue(value.value)
    && typeof value.kind === "string"
    && value.kind.trim() !== ""
    && (value.keySpan === null || isSpan(value.keySpan))
    && isSpan(value.valueSpan)
    && isSpan(value.span);
}

function isGrantArgumentValue(value) {
  return typeof value === "string"
    || typeof value === "number"
    || (Array.isArray(value) && value.every((item) => typeof item === "string"));
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
    const metadataDiagnostic = validateGraphCapabilityOwnerAuthorizationMetadata(ownerGoalAuthorizationEdges[0], graphNode, ownerGoal, fallbackSpan);
    if (metadataDiagnostic) {
      return metadataDiagnostic;
    }
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

function validateGraphEffectRequestMetadata(graphEdge, ownerStep, effectNode, fallbackSpan) {
  const data = graphEdge.data;
  const dataIsObject = isPlainObject(data);
  const nameMatchesTarget = dataIsObject && data.name === effectNode.label;
  const expressionMatchesTarget = dataIsObject && data.expression === effectNode.data?.expression;
  const familyMatchesTarget = dataIsObject && data.family === effectNode.data?.family;
  const actionMatchesTarget = dataIsObject && data.action === effectNode.data?.action;
  const contractIdMatchesTarget = dataIsObject && (data.contractId ?? null) === (effectNode.data?.contractId ?? null);
  const contractArgumentsMatchTarget = dataIsObject && contractArgumentsEqual(data.contractArguments, effectNode.data?.contractArguments ?? {});
  const argsMatchTarget = dataIsObject && stringMapsEqual(data.args, effectNode.data?.args ?? {});
  const argKindsMatchTarget = dataIsObject && stringMapsEqual(data.argKinds, effectNode.data?.argKinds ?? {});
  const argSpansMatchTarget = dataIsObject && spanMapsEqual(data.argSpans, effectNode.data?.argSpans ?? {});
  const sourceSpanMatchesStep = dataIsObject && spansEqual(data.sourceSpan, ownerStep?.span);
  const targetSpanMatchesEffect = dataIsObject && spansEqual(data.targetSpan, effectNode.span);
  if (
    dataIsObject
    && nameMatchesTarget
    && expressionMatchesTarget
    && familyMatchesTarget
    && actionMatchesTarget
    && contractIdMatchesTarget
    && contractArgumentsMatchTarget
    && argsMatchTarget
    && argKindsMatchTarget
    && argSpansMatchTarget
    && sourceSpanMatchesStep
    && targetSpanMatchesEffect
  ) {
    return null;
  }
  return error("INTENT_GRAPH_EFFECT_REQUEST_INVALID", `requests edge '${graphEdge.from}' to '${graphEdge.to}' must carry effect request metadata matching its owning step and target effect.`, edgeDiagnosticSpan(new Map([[ownerStep.id, ownerStep], [effectNode.id, effectNode]]), graphEdge, fallbackSpan), {
    effect: effectNode.label,
    effect_id: effectNode.id,
    owner_step_id: ownerStep?.id ?? null,
    request_edge: { from: graphEdge.from, to: graphEdge.to, kind: graphEdge.kind },
    data_is_object: dataIsObject,
    name_matches_target: nameMatchesTarget,
    expression_matches_target: expressionMatchesTarget,
    family_matches_target: familyMatchesTarget,
    action_matches_target: actionMatchesTarget,
    contract_id_matches_target: contractIdMatchesTarget,
    contract_arguments_match_target: contractArgumentsMatchTarget,
    args_match_target: argsMatchTarget,
    arg_kinds_match_target: argKindsMatchTarget,
    arg_spans_match_target: argSpansMatchTarget,
    source_span_matches_step: sourceSpanMatchesStep,
    target_span_matches_effect: targetSpanMatchesEffect,
  });
}

function stringMapsEqual(left, right) {
  if (!isPlainObject(left) || !isPlainObject(right)) {
    return false;
  }
  const leftEntries = Object.entries(left);
  const rightEntries = Object.entries(right);
  return leftEntries.length === rightEntries.length
    && leftEntries.every(([key, value]) => grantValuesEqual(value, right[key]));
}

function spanMapsEqual(left, right) {
  if (!isPlainObject(left) || !isPlainObject(right)) {
    return false;
  }
  const leftEntries = Object.entries(left);
  const rightEntries = Object.entries(right);
  return leftEntries.length === rightEntries.length
    && leftEntries.every(([key, value]) => spansEqual(value, right[key]));
}

function validateGraphMemory(graphNode, graphSpan) {
  if (graphNode.kind !== "Memory") {
    return null;
  }
  const retentionIsArray = Array.isArray(graphNode.data.retention);
  const retentionRulesIsArray = Array.isArray(graphNode.data.retentionRules);
  const keysIsArray = Array.isArray(graphNode.data.keys);
  const retentionRulesNonempty = retentionRulesIsArray && graphNode.data.retentionRules.length > 0;
  const invalidRetentionIndexes = retentionRulesIsArray
    ? graphNode.data.retentionRules
        .map((retentionRule, retentionIndex) => isGraphRetentionRuleRecord(retentionRule) ? null : retentionIndex)
        .filter((retentionIndex) => retentionIndex !== null)
    : [];
  const invalidKeyIndexes = keysIsArray
    ? graphNode.data.keys
        .map((key, keyIndex) => isGraphMemoryKeyRecord(key) ? null : keyIndex)
        .filter((keyIndex) => keyIndex !== null)
    : [];
  if (retentionIsArray && retentionRulesNonempty && invalidRetentionIndexes.length === 0 && keysIsArray && invalidKeyIndexes.length === 0) {
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
    keys_is_array: keysIsArray,
    invalid_key_indexes: invalidKeyIndexes,
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

function isGraphMemoryKeyRecord(value) {
  return isPlainObject(value)
    && value.kind === "MemoryKey"
    && typeof value.name === "string"
    && value.name.trim() !== ""
    && (value.type === null || (typeof value.type === "string" && value.type.trim() !== ""))
    && (value.typeSpan === null || isSpan(value.typeSpan))
    && typeof value.raw === "string"
    && value.raw.trim() !== ""
    && isSpan(value.span);
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
    const metadataDiagnostic = validateGraphMemoryDeclareMetadata(ownerGoalDeclareEdges[0], ownerGoal, graphNode, fallbackSpan);
    if (metadataDiagnostic) {
      return metadataDiagnostic;
    }
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

function validateGraphTypedEdgeContract(nodesById, graphEdge, fallbackSpan) {
  if (!["data", "supplies", "requires", "produces", "approves", "timeouts", "retries", "checkpoints", "gates", "verifies"].includes(graphEdge.kind)) {
    return null;
  }
  const sourceNode = nodesById.get(graphEdge.from);
  const targetNode = nodesById.get(graphEdge.to);
  const checks = typedEdgeChecks(graphEdge, sourceNode, targetNode);
  if (checks.length === 0 || checks.every((check) => check.ok)) {
    return null;
  }
  return error("INTENT_GRAPH_TYPED_EDGE_INVALID", `${graphEdge.kind} edge '${graphEdge.from}' to '${graphEdge.to}' must match endpoint names, types, ownership, and source spans.`, edgeDiagnosticSpan(nodesById, graphEdge, fallbackSpan), {
    edge: graphEdge.kind,
    from: graphEdge.from,
    to: graphEdge.to,
    checks,
  });
}

function typedEdgeChecks(graphEdge, sourceNode, targetNode) {
  if (graphEdge.kind === "produces") {
    return producesEdgeChecks(graphEdge, sourceNode, targetNode);
  }
  if (graphEdge.kind === "data") {
    return dataEdgeChecks(graphEdge, sourceNode, targetNode);
  }
  if (graphEdge.kind === "supplies") {
    return suppliesEdgeChecks(graphEdge, sourceNode, targetNode);
  }
  if (graphEdge.kind === "requires") {
    return requiresEdgeChecks(graphEdge, sourceNode, targetNode);
  }
  if (graphEdge.kind === "approves") {
    return approvesEdgeChecks(graphEdge, sourceNode, targetNode);
  }
  if (graphEdge.kind === "timeouts" || graphEdge.kind === "retries") {
    return policyEdgeChecks(graphEdge, sourceNode, targetNode);
  }
  if (graphEdge.kind === "checkpoints") {
    return checkpointEdgeChecks(graphEdge, sourceNode, targetNode);
  }
  if (graphEdge.kind === "gates") {
    return gatesEdgeChecks(graphEdge, sourceNode, targetNode);
  }
  if (graphEdge.kind === "verifies") {
    return verifiesEdgeChecks(graphEdge, sourceNode, targetNode);
  }
  return [];
}

function producesEdgeChecks(graphEdge, sourceNode, targetNode) {
  if (sourceNode?.kind !== "Step" || targetNode?.kind !== "Completion") {
    return [];
  }
  const payloadType = normalizeTypeRefOrNull(graphEdge.data?.type);
  const stepOutputType = normalizeTypeRefOrNull(sourceNode.data?.outputType);
  const completionOutputType = normalizeTypeRefOrNull(targetNode.data?.outputType);
  return [
    typedCheck("type_matches_source", payloadType !== null && payloadType === stepOutputType, graphEdge.data?.type, sourceNode.data?.outputType),
    typedCheck("type_matches_target", completionOutputType === null || payloadType === completionOutputType, graphEdge.data?.type, targetNode.data?.outputType),
    typedCheck("source_span_matches_source", spansEqual(graphEdge.data?.sourceSpan, sourceNode.data?.outputTypeSpan), graphEdge.data?.sourceSpan, sourceNode.data?.outputTypeSpan),
    typedCheck("target_span_matches_target", spansEqual(graphEdge.data?.targetSpan, completionOutputSpan(targetNode)), graphEdge.data?.targetSpan, completionOutputSpan(targetNode)),
  ];
}

function dataEdgeChecks(graphEdge, sourceNode, targetNode) {
  if (!targetNode || targetNode.kind !== "Input" || targetNode.data?.scope !== "step") {
    return [];
  }
  const sourceType = graphProducerType(sourceNode);
  const sourceSpan = graphProducerSpan(sourceNode);
  const payloadType = normalizeTypeRefOrNull(graphEdge.data?.type);
  const targetType = normalizeTypeRefOrNull(targetNode.data?.type);
  return [
    typedCheck("parameter_matches_target", graphEdge.data?.parameter === targetNode.label, graphEdge.data?.parameter, targetNode.label),
    typedCheck("type_matches_source", payloadType !== null && payloadType === sourceType, graphEdge.data?.type, graphProducerTypeLabel(sourceNode)),
    typedCheck("type_matches_target", payloadType !== null && payloadType === targetType, graphEdge.data?.type, targetNode.data?.type),
    typedCheck("source_span_matches_source", spansEqual(graphEdge.data?.sourceSpan, sourceSpan), graphEdge.data?.sourceSpan, sourceSpan),
    typedCheck("target_span_matches_target", spansEqual(graphEdge.data?.targetSpan, targetNode.span), graphEdge.data?.targetSpan, targetNode.span),
  ];
}

function suppliesEdgeChecks(graphEdge, sourceNode, targetNode) {
  if (sourceNode?.kind !== "Input" || sourceNode.data?.scope !== "goal" || targetNode?.kind !== "Goal") {
    return [];
  }
  const sourceType = normalizeTypeRefOrNull(sourceNode.data?.type);
  const payloadType = normalizeTypeRefOrNull(graphEdge.data?.type);
  return [
    typedCheck("owner_goal_matches_target", parentNodeId(sourceNode.id, ":input:") === targetNode.id, parentNodeId(sourceNode.id, ":input:"), targetNode.id),
    typedCheck("parameter_matches_source", graphEdge.data?.parameter === sourceNode.label, graphEdge.data?.parameter, sourceNode.label),
    typedCheck("type_matches_source", payloadType !== null && payloadType === sourceType, graphEdge.data?.type, sourceNode.data?.type),
    typedCheck("source_span_matches_source", spansEqual(graphEdge.data?.sourceSpan, sourceNode.span), graphEdge.data?.sourceSpan, sourceNode.span),
    typedCheck("target_span_matches_source", spansEqual(graphEdge.data?.targetSpan, sourceNode.span), graphEdge.data?.targetSpan, sourceNode.span),
  ];
}

function requiresEdgeChecks(graphEdge, sourceNode, targetNode) {
  if (sourceNode?.kind === "Input" && targetNode?.kind === "Step") {
    const sourceType = normalizeTypeRefOrNull(sourceNode.data?.type);
    const payloadType = normalizeTypeRefOrNull(graphEdge.data?.type);
    return [
      typedCheck("owner_step_matches_target", parentNodeId(sourceNode.id, ":input:") === targetNode.id, parentNodeId(sourceNode.id, ":input:"), targetNode.id),
      typedCheck("parameter_matches_source", graphEdge.data?.parameter === sourceNode.label, graphEdge.data?.parameter, sourceNode.label),
      typedCheck("type_matches_source", payloadType !== null && payloadType === sourceType, graphEdge.data?.type, sourceNode.data?.type),
      typedCheck("target_span_matches_source", spansEqual(graphEdge.data?.targetSpan, sourceNode.span), graphEdge.data?.targetSpan, sourceNode.span),
    ];
  }
  if (sourceNode?.kind === "Check" && sourceNode.data?.scope === "step" && targetNode?.kind === "Step") {
    return [
      typedCheck("owner_step_matches_target", parentNodeId(sourceNode.id, ":requirement:") === targetNode.id, parentNodeId(sourceNode.id, ":requirement:"), targetNode.id),
      typedCheck("requirement_matches_source", graphEdge.data?.requirement === sourceNode.data?.requirement, graphEdge.data?.requirement, sourceNode.data?.requirement),
    ];
  }
  return [];
}

function approvesEdgeChecks(graphEdge, sourceNode, targetNode) {
  if (sourceNode?.kind !== "Approval" || (targetNode?.kind !== "Step" && targetNode?.kind !== "Effect")) {
    return [];
  }
  const ownerStepId = parentNodeId(sourceNode.id, ":approval:");
  const targetOwnerStepId = targetNode.kind === "Step" ? targetNode.id : parentNodeId(targetNode.id, ":effect:");
  return [
    typedCheck("owner_step_matches_target", ownerStepId === targetOwnerStepId, ownerStepId, targetOwnerStepId),
    typedCheck("approval_matches_source", graphEdge.data?.approval === sourceNode.data?.approval, graphEdge.data?.approval, sourceNode.data?.approval),
  ];
}

function policyEdgeChecks(graphEdge, sourceNode, targetNode) {
  if (sourceNode?.kind !== "Policy" || targetNode?.kind !== "Step") {
    return [];
  }
  const marker = graphEdge.kind === "timeouts" ? ":timeout:" : ":retry:";
  const expectedPolicyKind = graphEdge.kind === "timeouts" ? "timeout" : "retry";
  return [
    typedCheck("owner_step_matches_target", parentNodeId(sourceNode.id, marker) === targetNode.id, parentNodeId(sourceNode.id, marker), targetNode.id),
    typedCheck("policy_kind_matches_edge", sourceNode.data?.policyKind === expectedPolicyKind, sourceNode.data?.policyKind, expectedPolicyKind),
    typedCheck("policy_matches_source", graphEdge.data?.policy === sourceNode.data?.policy, graphEdge.data?.policy, sourceNode.data?.policy),
  ];
}

function checkpointEdgeChecks(graphEdge, sourceNode, targetNode) {
  if (sourceNode?.kind !== "Step" || targetNode?.kind !== "Checkpoint") {
    return [];
  }
  return [
    typedCheck("owner_step_matches_source", parentNodeId(targetNode.id, ":checkpoint:") === sourceNode.id, parentNodeId(targetNode.id, ":checkpoint:"), sourceNode.id),
    typedCheck("checkpoint_matches_target", graphEdge.data?.checkpoint === targetNode.data?.checkpoint, graphEdge.data?.checkpoint, targetNode.data?.checkpoint),
  ];
}

function gatesEdgeChecks(graphEdge, sourceNode, targetNode) {
  if (sourceNode?.kind !== "Check" || targetNode?.kind !== "Goal") {
    return [];
  }
  const sourceScope = graphCheckScope(sourceNode);
  return [
    typedCheck("owner_goal_matches_target", checkOwnerGoalId(sourceNode.id) === targetNode.id, checkOwnerGoalId(sourceNode.id), targetNode.id),
    typedCheck("requirement_matches_source", graphEdge.data?.requirement === sourceNode.data?.requirement, graphEdge.data?.requirement, sourceNode.data?.requirement),
    typedCheck("scope_matches_source", graphEdge.data?.scope === sourceScope, graphEdge.data?.scope, sourceScope),
    typedCheck("source_span_matches_source", spansEqual(graphEdge.data?.sourceSpan, sourceNode.span), graphEdge.data?.sourceSpan, sourceNode.span),
    typedCheck("target_span_matches_target", spansEqual(graphEdge.data?.targetSpan, targetNode.span), graphEdge.data?.targetSpan, targetNode.span),
  ];
}

function verifiesEdgeChecks(graphEdge, sourceNode, targetNode) {
  if (sourceNode?.kind !== "Check" || targetNode?.kind !== "Completion") {
    return [];
  }
  const ownerGoalId = checkOwnerGoalId(sourceNode.id);
  const sourceScope = graphCheckScope(sourceNode);
  const expectedCompletionId = ownerGoalId ? `${ownerGoalId}:completion` : null;
  return [
    typedCheck("owner_completion_matches_target", expectedCompletionId === targetNode.id, expectedCompletionId, targetNode.id),
    typedCheck("requirement_matches_source", graphEdge.data?.requirement === sourceNode.data?.requirement, graphEdge.data?.requirement, sourceNode.data?.requirement),
    typedCheck("scope_matches_source", graphEdge.data?.scope === sourceScope, graphEdge.data?.scope, sourceScope),
    typedCheck("source_span_matches_source", spansEqual(graphEdge.data?.sourceSpan, sourceNode.span), graphEdge.data?.sourceSpan, sourceNode.span),
    typedCheck("target_span_matches_target", spansEqual(graphEdge.data?.targetSpan, targetNode.span), graphEdge.data?.targetSpan, targetNode.span),
  ];
}

function graphCheckScope(sourceNode) {
  return sourceNode?.data?.scope === "step" ? "step" : "goal";
}

function completionOutputSpan(targetNode) {
  if (targetNode?.data?.outputType === null) {
    return targetNode.span;
  }
  return targetNode?.data?.outputTypeSpan;
}

function graphProducerType(sourceNode) {
  return normalizeTypeRefOrNull(graphProducerTypeLabel(sourceNode));
}

function graphProducerTypeLabel(sourceNode) {
  if (sourceNode?.kind === "Input" && sourceNode.data?.scope === "goal") {
    return sourceNode.data?.type;
  }
  if (sourceNode?.kind === "Step") {
    return sourceNode.data?.outputType;
  }
  return null;
}

function graphProducerSpan(sourceNode) {
  if (sourceNode?.kind === "Input" && sourceNode.data?.scope === "goal") {
    return sourceNode.span;
  }
  if (sourceNode?.kind === "Step") {
    return sourceNode.data?.outputTypeSpan;
  }
  return null;
}

function normalizeTypeRefOrNull(value) {
  return typeof value === "string" && value.trim() !== "" ? normalizeTypeRef(value) : null;
}

function typedCheck(name, ok, actual, expected) {
  return { name, ok, actual: typedValue(actual), expected: typedValue(expected) };
}

function typedValue(value) {
  if (isSpan(value)) {
    return value;
  }
  return typeof value === "string" ? value : null;
}

function spansEqual(left, right) {
  return isSpan(left)
    && isSpan(right)
    && left.file === right.file
    && left.start.line === right.start.line
    && left.start.column === right.start.column
    && left.start.offset === right.start.offset
    && left.end.line === right.end.line
    && left.end.column === right.end.column
    && left.end.offset === right.end.offset;
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
  const outputTypeSpanIsValid = isGraphOutputTypeSpanValid(graphNode.data.outputType, graphNode.data.outputTypeSpan);
  const effectsAreValid = isNonemptyStringArray(graphNode.data.effects);
  const requirementsAreValid = isNonemptyStringArray(graphNode.data.requirements);
  const checkpointsAreValid = isNonemptyStringArray(graphNode.data.checkpoints);
  const approvalsAreValid = isNonemptyStringArray(graphNode.data.approvals);
  const timeoutsAreValid = isNonemptyStringArray(graphNode.data.timeouts);
  const retriesAreValid = isNonemptyStringArray(graphNode.data.retries);
  const memoryAccessesAreValid = isNonemptyStringArray(graphNode.data.memoryAccesses);
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
    && memoryAccessesAreValid
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
    memory_accesses_are_valid: memoryAccessesAreValid,
  });
}

function validateGraphStepMetadata(nodesById, incomingEdgesByNode, outgoingEdgesByNode, graphNode, fallbackSpan) {
  return [
    validateGraphStepInputMetadata(nodesById, incomingEdgesByNode, graphNode, fallbackSpan),
    ...stepMetadataSpecs(nodesById, incomingEdgesByNode, outgoingEdgesByNode, graphNode)
      .map((spec) => validateGraphStepMetadataField(graphNode, spec, fallbackSpan)),
  ].filter((diagnostic) => diagnostic !== null);
}

function validateGraphStepInputMetadata(nodesById, incomingEdgesByNode, graphNode, fallbackSpan) {
  const declaredInputs = graphNode.data?.inputs;
  const ownedInputs = ownedIncomingNodes(nodesById, incomingEdgesByNode, graphNode.id, "requires", "Input")
    .filter((ownedNode) => ownedNode.data?.scope === "step");
  if (!Array.isArray(declaredInputs) || declaredInputs.some((input) => !isGraphParameterRecord(input)) || (declaredInputs.length === 0 && ownedInputs.length === 0)) {
    return null;
  }
  const ownedValues = ownedInputs.map((ownedNode) => ({
    name: ownedNode.label,
    type: ownedNode.data?.type,
    span: ownedNode.span,
  }));
  if (parameterArraysEqual(declaredInputs, ownedValues)) {
    return null;
  }
  return error("INTENT_GRAPH_STEP_METADATA_INVALID", `step '${graphNode.label}' inputs metadata must match owned step input nodes in source order.`, graphNode.span ?? fallbackSpan, {
    step: graphNode.label,
    step_id: graphNode.id,
    field: "inputs",
    declared_values: declaredInputs,
    owned_values: ownedValues,
    owned_node_ids: ownedInputs.map((ownedNode) => ownedNode.id),
    declared_count: declaredInputs.length,
    owned_count: ownedInputs.length,
    mismatched_indexes: mismatchedParameterIndexes(declaredInputs, ownedValues),
  });
}

function validateGraphStepMetadataField(graphNode, spec, fallbackSpan) {
  const declaredValues = graphNode.data?.[spec.field];
  if (!isNonemptyStringArray(declaredValues) || (declaredValues.length === 0 && spec.ownedRecords.length === 0)) {
    return null;
  }
  const ownedValues = spec.ownedRecords.map((ownedRecord) => {
    const value = spec.value(ownedRecord);
    return typeof value === "string" ? value : null;
  });
  if (stringArraysEqual(declaredValues, ownedValues)) {
    return null;
  }
  return error("INTENT_GRAPH_STEP_METADATA_INVALID", `step '${graphNode.label}' ${spec.field} metadata must match owned child nodes in source order.`, graphNode.span ?? fallbackSpan, {
    step: graphNode.label,
    step_id: graphNode.id,
    field: spec.field,
    declared_values: declaredValues,
    owned_values: ownedValues,
    owned_node_ids: spec.ownedRecords.map((ownedRecord) => spec.nodeId(ownedRecord)),
    declared_count: declaredValues.length,
    owned_count: spec.ownedRecords.length,
    mismatched_indexes: mismatchedIndexes(declaredValues, ownedValues),
  });
}

function stepMetadataSpecs(nodesById, incomingEdgesByNode, outgoingEdgesByNode, graphNode) {
  return [
    {
      field: "effects",
      ownedRecords: ownedOutgoingNodes(nodesById, outgoingEdgesByNode, graphNode.id, "requests", "Effect"),
      value: (ownedNode) => ownedNode.label,
      nodeId: (ownedNode) => ownedNode.id,
    },
    {
      field: "requirements",
      ownedRecords: ownedIncomingNodes(nodesById, incomingEdgesByNode, graphNode.id, "requires", "Check")
        .filter((ownedNode) => ownedNode.data?.scope === "step"),
      value: (ownedNode) => ownedNode.data?.requirement,
      nodeId: (ownedNode) => ownedNode.id,
    },
    {
      field: "checkpoints",
      ownedRecords: ownedOutgoingNodes(nodesById, outgoingEdgesByNode, graphNode.id, "checkpoints", "Checkpoint"),
      value: (ownedNode) => ownedNode.data?.checkpoint,
      nodeId: (ownedNode) => ownedNode.id,
    },
    {
      field: "approvals",
      ownedRecords: ownedIncomingNodes(nodesById, incomingEdgesByNode, graphNode.id, "approves", "Approval"),
      value: (ownedNode) => ownedNode.data?.approval,
      nodeId: (ownedNode) => ownedNode.id,
    },
    {
      field: "timeouts",
      ownedRecords: ownedIncomingNodes(nodesById, incomingEdgesByNode, graphNode.id, "timeouts", "Policy")
        .filter((ownedNode) => ownedNode.data?.policyKind === "timeout"),
      value: (ownedNode) => ownedNode.data?.policy,
      nodeId: (ownedNode) => ownedNode.id,
    },
    {
      field: "retries",
      ownedRecords: ownedIncomingNodes(nodesById, incomingEdgesByNode, graphNode.id, "retries", "Policy")
        .filter((ownedNode) => ownedNode.data?.policyKind === "retry"),
      value: (ownedNode) => ownedNode.data?.policy,
      nodeId: (ownedNode) => ownedNode.id,
    },
    {
      field: "memoryAccesses",
      ownedRecords: ownedMemoryAccessEdges(nodesById, incomingEdgesByNode, outgoingEdgesByNode, graphNode.id),
      value: (graphEdge) => graphEdge.data?.target,
      nodeId: (graphEdge) => {
        const sourceNode = nodesById.get(graphEdge.from);
        return sourceNode?.kind === "Memory" ? graphEdge.from : graphEdge.to;
      },
    },
  ];
}

function ownedOutgoingNodes(nodesById, outgoingEdgesByNode, stepId, edgeKind, nodeKind) {
  return (outgoingEdgesByNode.get(stepId) ?? [])
    .filter((graphEdge) => graphEdge.kind === edgeKind && nodesById.get(graphEdge.to)?.kind === nodeKind)
    .map((graphEdge) => nodesById.get(graphEdge.to))
    .sort(compareGraphNodesBySpan);
}

function ownedIncomingNodes(nodesById, incomingEdgesByNode, stepId, edgeKind, nodeKind) {
  return (incomingEdgesByNode.get(stepId) ?? [])
    .filter((graphEdge) => graphEdge.kind === edgeKind && nodesById.get(graphEdge.from)?.kind === nodeKind)
    .map((graphEdge) => nodesById.get(graphEdge.from))
    .sort(compareGraphNodesBySpan);
}

function ownedMemoryAccessEdges(nodesById, incomingEdgesByNode, outgoingEdgesByNode, stepId) {
  const readOrCiteEdges = (incomingEdgesByNode.get(stepId) ?? [])
    .filter((graphEdge) => ["reads", "cites"].includes(graphEdge.kind) && nodesById.get(graphEdge.from)?.kind === "Memory");
  const writeEdges = (outgoingEdgesByNode.get(stepId) ?? [])
    .filter((graphEdge) => graphEdge.kind === "writes" && nodesById.get(graphEdge.to)?.kind === "Memory");
  return [...readOrCiteEdges, ...writeEdges].sort(compareGraphMemoryAccessEdgesBySpan);
}

function compareGraphNodesBySpan(left, right) {
  return spanStartOffset(left.span) - spanStartOffset(right.span);
}

function compareGraphMemoryAccessEdgesBySpan(left, right) {
  return spanStartOffset(graphMemoryAccessSpan(left)) - spanStartOffset(graphMemoryAccessSpan(right));
}

function graphMemoryAccessSpan(graphEdge) {
  return graphEdge.kind === "writes" ? graphEdge.data?.sourceSpan : graphEdge.data?.targetSpan;
}

function stringArraysEqual(left, right) {
  return left.length === right.length && left.every((value, index) => value === right[index]);
}

function parameterArraysEqual(left, right) {
  return left.length === right.length && left.every((value, index) => parametersEqual(value, right[index]));
}

function parametersEqual(left, right) {
  return left?.name === right?.name && left?.type === right?.type && spansEqual(left?.span, right?.span);
}

function mismatchedIndexes(left, right) {
  const indexes = [];
  const length = Math.max(left.length, right.length);
  for (let index = 0; index < length; index += 1) {
    if (left[index] !== right[index]) {
      indexes.push(index);
    }
  }
  return indexes;
}

function mismatchedParameterIndexes(left, right) {
  const indexes = [];
  const length = Math.max(left.length, right.length);
  for (let index = 0; index < length; index += 1) {
    if (!parametersEqual(left[index], right[index])) {
      indexes.push(index);
    }
  }
  return indexes;
}

function isGraphOutputTypeSpanValid(outputType, outputTypeSpan) {
  if (outputType === null) {
    return outputTypeSpan === null;
  }
  return typeof outputType === "string" && outputType.trim() !== "" && isSpan(outputTypeSpan);
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
    "supplies",
    "produces",
    "requires",
    "approves",
    "timeouts",
    "retries",
    "checkpoints",
    "gates",
    "verifies",
    "reads",
    "writes",
    "cites",
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
  const scopeIsValid = payload.scope === "goal" || payload.scope === "step";
  const accessIsValid = payload.access === "read" || payload.access === "write" || payload.access === "cite";
  const memoryIsNonempty = typeof payload.memory === "string" && payload.memory.trim() !== "";
  const targetIsNonempty = typeof payload.target === "string" && payload.target.trim() !== "";
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
  const suppliesGoalInput = graphEdge.kind === "supplies"
    && sourceNode?.kind === "Input"
    && sourceNode.data?.scope === "goal"
    && targetNode?.kind === "Goal";
  const gatesCheck = graphEdge.kind === "gates"
    && sourceNode?.kind === "Check"
    && targetNode?.kind === "Goal";
  const verifiesCheck = graphEdge.kind === "verifies"
    && sourceNode?.kind === "Check"
    && targetNode?.kind === "Completion";
  const memoryAccess = ["reads", "writes", "cites"].includes(graphEdge.kind);
  const payloadIsValid = graphEdge.kind === "data"
    ? parameterIsNonempty && typeIsNonempty && sourceSpanIsValid && targetSpanIsValid
    : suppliesGoalInput
      ? parameterIsNonempty && typeIsNonempty && sourceSpanIsValid && targetSpanIsValid
    : gatesCheck || verifiesCheck
      ? requirementIsNonempty && scopeIsValid && sourceSpanIsValid && targetSpanIsValid
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
              : stepCheckpoints
                ? checkpointIsNonempty
                : !memoryAccess || (accessIsValid && memoryIsNonempty && targetIsNonempty && sourceSpanIsValid && targetSpanIsValid);
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
    scope: typeof payload.scope === "string" ? payload.scope : null,
    access: typeof payload.access === "string" ? payload.access : null,
    memory: typeof payload.memory === "string" ? payload.memory : null,
    target: typeof payload.target === "string" ? payload.target : null,
    parameter_is_nonempty: parameterIsNonempty,
    type_is_nonempty: typeIsNonempty,
    requirement_is_nonempty: requirementIsNonempty,
    approval_is_nonempty: approvalIsNonempty,
    policy_is_nonempty: policyIsNonempty,
    checkpoint_is_nonempty: checkpointIsNonempty,
    scope_is_valid: scopeIsValid,
    access_is_valid: accessIsValid,
    memory_is_nonempty: memoryIsNonempty,
    target_is_nonempty: targetIsNonempty,
    source_span_is_valid: sourceSpanIsValid,
    target_span_is_valid: targetSpanIsValid,
  });
}

function validateGraphEdgeRole(nodesById, graphEdge, fallbackSpan) {
  if (!["declares", "authorizes", "requests", "gates", "verifies", "plans", "completes", "produces", "constrains", "guards", "requires", "approves", "checkpoints", "timeouts", "retries", "data", "supplies", "informs", "precedes", "reads", "writes", "cites"].includes(graphEdge.kind)) {
    return null;
  }
  const sourceNode = nodesById.get(graphEdge.from);
  const targetNode = nodesById.get(graphEdge.to);
  if (graphEdge.kind === "data") {
    return validateGraphDataEdgeRole(nodesById, graphEdge, sourceNode, targetNode, fallbackSpan);
  }
  if (graphEdge.kind === "supplies") {
    return validateGraphSuppliesEdgeRole(nodesById, graphEdge, sourceNode, targetNode, fallbackSpan);
  }
  if (graphEdge.kind === "informs") {
    return validateGraphInformsEdgeRole(nodesById, graphEdge, sourceNode, targetNode, fallbackSpan);
  }
  if (graphEdge.kind === "precedes") {
    return validateGraphPrecedesEdgeRole(nodesById, graphEdge, sourceNode, targetNode, fallbackSpan);
  }
  if (graphEdge.kind === "reads" || graphEdge.kind === "writes" || graphEdge.kind === "cites") {
    return validateGraphMemoryAccessEdgeRole(nodesById, graphEdge, sourceNode, targetNode, fallbackSpan);
  }
  if (graphEdge.kind === "requires") {
    return validateGraphRequiresEdgeRole(nodesById, graphEdge, sourceNode, targetNode, fallbackSpan);
  }
  if (graphEdge.kind === "approves") {
    return validateGraphApprovesEdgeRole(nodesById, graphEdge, sourceNode, targetNode, fallbackSpan);
  }
  if (graphEdge.kind === "checkpoints") {
    return validateGraphCheckpointsEdgeRole(nodesById, graphEdge, sourceNode, targetNode, fallbackSpan);
  }
  if (graphEdge.kind === "timeouts" || graphEdge.kind === "retries") {
    return validateGraphPolicyEdgeRole(nodesById, graphEdge, sourceNode, targetNode, fallbackSpan);
  }
  if (graphEdge.kind === "constrains") {
    return validateGraphConstrainsEdgeRole(nodesById, graphEdge, sourceNode, targetNode, fallbackSpan);
  }
  if (graphEdge.kind === "guards") {
    return validateGraphGuardsEdgeRole(nodesById, graphEdge, sourceNode, targetNode, fallbackSpan);
  }
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

function validateGraphDataEdgeRole(nodesById, graphEdge, sourceNode, targetNode, fallbackSpan) {
  const sourceIsProducer = (sourceNode?.kind === "Input" && sourceNode.data?.scope === "goal") || sourceNode?.kind === "Step";
  const targetIsStepInput = targetNode?.kind === "Input" && targetNode.data?.scope === "step";
  if (sourceIsProducer && targetIsStepInput) {
    return null;
  }
  return error("INTENT_GRAPH_DATA_ROLE_INVALID", `data edge '${graphEdge.from}' to '${graphEdge.to}' must connect a goal input or step producer to a step input.`, edgeDiagnosticSpan(nodesById, graphEdge, fallbackSpan), {
    edge: graphEdge.kind,
    from: graphEdge.from,
    to: graphEdge.to,
    from_kind: sourceNode?.kind ?? null,
    to_kind: targetNode?.kind ?? null,
    from_scope: sourceNode?.data?.scope ?? null,
    to_scope: targetNode?.data?.scope ?? null,
    supported_roles: [
      { from_kind: "Input", from_scope: "goal", to_kind: "Input", to_scope: "step" },
      { from_kind: "Step", to_kind: "Input", to_scope: "step" },
    ],
  });
}

function validateGraphSuppliesEdgeRole(nodesById, graphEdge, sourceNode, targetNode, fallbackSpan) {
  if (sourceNode?.kind === "Input" && sourceNode.data?.scope === "goal" && targetNode?.kind === "Goal") {
    return null;
  }
  return error("INTENT_GRAPH_SUPPLY_INVALID", `supplies edge '${graphEdge.from}' to '${graphEdge.to}' must connect a goal input to a Goal node.`, edgeDiagnosticSpan(nodesById, graphEdge, fallbackSpan), {
    edge: graphEdge.kind,
    from: graphEdge.from,
    to: graphEdge.to,
    from_kind: sourceNode?.kind ?? null,
    to_kind: targetNode?.kind ?? null,
    from_scope: sourceNode?.data?.scope ?? null,
    supported_roles: [
      { from_kind: "Input", from_scope: "goal", to_kind: "Goal" },
    ],
  });
}

function validateGraphInformsEdgeRole(nodesById, graphEdge, sourceNode, targetNode, fallbackSpan) {
  if (sourceNode?.kind === "Context" && targetNode?.kind === "Goal") {
    return null;
  }
  return error("INTENT_GRAPH_INFORM_INVALID", `informs edge '${graphEdge.from}' to '${graphEdge.to}' must connect a Context node to a Goal node.`, edgeDiagnosticSpan(nodesById, graphEdge, fallbackSpan), {
    edge: graphEdge.kind,
    from: graphEdge.from,
    to: graphEdge.to,
    from_kind: sourceNode?.kind ?? null,
    to_kind: targetNode?.kind ?? null,
    supported_roles: [
      { from_kind: "Context", to_kind: "Goal" },
    ],
  });
}

function validateGraphPrecedesEdgeRole(nodesById, graphEdge, sourceNode, targetNode, fallbackSpan) {
  if (sourceNode?.kind === "Step" && targetNode?.kind === "Step") {
    return null;
  }
  return error("INTENT_GRAPH_PRECEDE_INVALID", `precedes edge '${graphEdge.from}' to '${graphEdge.to}' must connect a Step node to a Step node.`, edgeDiagnosticSpan(nodesById, graphEdge, fallbackSpan), {
    edge: graphEdge.kind,
    from: graphEdge.from,
    to: graphEdge.to,
    from_kind: sourceNode?.kind ?? null,
    to_kind: targetNode?.kind ?? null,
    supported_roles: [
      { from_kind: "Step", to_kind: "Step" },
    ],
  });
}

function validateGraphMemoryAccessEdgeRole(nodesById, graphEdge, sourceNode, targetNode, fallbackSpan) {
  const readsOrCites = (graphEdge.kind === "reads" || graphEdge.kind === "cites") && sourceNode?.kind === "Memory" && targetNode?.kind === "Step";
  const writes = graphEdge.kind === "writes" && sourceNode?.kind === "Step" && targetNode?.kind === "Memory";
  if (readsOrCites || writes) {
    return null;
  }
  return error("INTENT_GRAPH_MEMORY_ACCESS_INVALID", `${graphEdge.kind} edge '${graphEdge.from}' to '${graphEdge.to}' must connect memory access roles.`, edgeDiagnosticSpan(nodesById, graphEdge, fallbackSpan), {
    edge: graphEdge.kind,
    from: graphEdge.from,
    to: graphEdge.to,
    from_kind: sourceNode?.kind ?? null,
    to_kind: targetNode?.kind ?? null,
    supported_roles: [
      { edge: "reads", from_kind: "Memory", to_kind: "Step" },
      { edge: "cites", from_kind: "Memory", to_kind: "Step" },
      { edge: "writes", from_kind: "Step", to_kind: "Memory" },
    ],
  });
}

function validateGraphMemoryTarget(nodesById, graphEdge, fallbackSpan) {
  if (!["reads", "writes", "cites"].includes(graphEdge.kind)) {
    return null;
  }
  const sourceNode = nodesById.get(graphEdge.from);
  const targetNode = nodesById.get(graphEdge.to);
  const memoryNode = sourceNode?.kind === "Memory" ? sourceNode : targetNode?.kind === "Memory" ? targetNode : null;
  const key = graphEdge.data?.key;
  if (!memoryNode || key === null || key === undefined) {
    return null;
  }
  const declaredKeys = graphMemoryDeclaredKeys(memoryNode);
  if (typeof key === "string" && declaredKeys.has(key)) {
    return null;
  }
  return error("INTENT_GRAPH_MEMORY_TARGET_INVALID", `${graphEdge.kind} edge '${graphEdge.from}' to '${graphEdge.to}' must target a retained memory key.`, edgeDiagnosticSpan(nodesById, graphEdge, fallbackSpan), {
    edge: graphEdge.kind,
    from: graphEdge.from,
    to: graphEdge.to,
    memory_id: memoryNode.id,
    memory: graphEdge.data?.memory ?? null,
    key: typeof key === "string" ? key : null,
    target: graphEdge.data?.target ?? null,
    declared_keys: [...declaredKeys.keys()],
  });
}

function graphMemoryRetentionSubjects(graphNode) {
  const subjects = new Map();
  for (const retention of graphNode.data?.retentionRules ?? []) {
    if (retention?.subject?.raw) {
      subjects.set(retention.subject.raw, retention);
    }
  }
  return subjects;
}

function graphMemoryDeclaredKeys(graphNode) {
  const keys = graphMemoryRetentionSubjects(graphNode);
  for (const key of graphNode.data?.keys ?? []) {
    if (key?.name) {
      keys.set(key.name, key);
    }
  }
  return keys;
}

function validateGraphRequiresEdgeRole(nodesById, graphEdge, sourceNode, targetNode, fallbackSpan) {
  const isStepInput = sourceNode?.kind === "Input" && targetNode?.kind === "Step";
  const isStepRequirement = sourceNode?.kind === "Check" && sourceNode.data?.scope === "step" && targetNode?.kind === "Step";
  if (isStepInput || isStepRequirement) {
    return null;
  }
  return error("INTENT_GRAPH_REQUIRE_INVALID", `requires edge '${graphEdge.from}' to '${graphEdge.to}' must connect a step Input or step-scoped Check node to a Step node.`, edgeDiagnosticSpan(nodesById, graphEdge, fallbackSpan), {
    edge: graphEdge.kind,
    from: graphEdge.from,
    to: graphEdge.to,
    from_kind: sourceNode?.kind ?? null,
    to_kind: targetNode?.kind ?? null,
    from_scope: sourceNode?.data?.scope ?? null,
    supported_roles: [
      { from_kind: "Input", to_kind: "Step" },
      { from_kind: "Check", from_scope: "step", to_kind: "Step" },
    ],
  });
}

function validateGraphApprovesEdgeRole(nodesById, graphEdge, sourceNode, targetNode, fallbackSpan) {
  const isSupportedTarget = targetNode?.kind === "Step" || targetNode?.kind === "Effect";
  if (sourceNode?.kind === "Approval" && isSupportedTarget) {
    return null;
  }
  return error("INTENT_GRAPH_APPROVE_INVALID", `approves edge '${graphEdge.from}' to '${graphEdge.to}' must connect an Approval node to a Step or Effect node.`, edgeDiagnosticSpan(nodesById, graphEdge, fallbackSpan), {
    edge: graphEdge.kind,
    from: graphEdge.from,
    to: graphEdge.to,
    from_kind: sourceNode?.kind ?? null,
    to_kind: targetNode?.kind ?? null,
    supported_roles: [
      { from_kind: "Approval", to_kind: "Step" },
      { from_kind: "Approval", to_kind: "Effect" },
    ],
  });
}

function validateGraphCheckpointsEdgeRole(nodesById, graphEdge, sourceNode, targetNode, fallbackSpan) {
  if (sourceNode?.kind === "Step" && targetNode?.kind === "Checkpoint") {
    return null;
  }
  return error("INTENT_GRAPH_CHECKPOINT_EDGE_INVALID", `checkpoints edge '${graphEdge.from}' to '${graphEdge.to}' must connect a Step node to a Checkpoint node.`, edgeDiagnosticSpan(nodesById, graphEdge, fallbackSpan), {
    edge: graphEdge.kind,
    from: graphEdge.from,
    to: graphEdge.to,
    from_kind: sourceNode?.kind ?? null,
    to_kind: targetNode?.kind ?? null,
    supported_roles: [
      { from_kind: "Step", to_kind: "Checkpoint" },
    ],
  });
}

function validateGraphPolicyEdgeRole(nodesById, graphEdge, sourceNode, targetNode, fallbackSpan) {
  if (sourceNode?.kind === "Policy" && targetNode?.kind === "Step") {
    return null;
  }
  return error("INTENT_GRAPH_POLICY_EDGE_INVALID", `${graphEdge.kind} edge '${graphEdge.from}' to '${graphEdge.to}' must connect a Policy node to a Step node.`, edgeDiagnosticSpan(nodesById, graphEdge, fallbackSpan), {
    edge: graphEdge.kind,
    from: graphEdge.from,
    to: graphEdge.to,
    from_kind: sourceNode?.kind ?? null,
    to_kind: targetNode?.kind ?? null,
    supported_roles: [
      { from_kind: "Policy", to_kind: "Step" },
    ],
  });
}

function validateGraphConstrainsEdgeRole(nodesById, graphEdge, sourceNode, targetNode, fallbackSpan) {
  if (sourceNode?.kind === "Invariant" && targetNode?.kind === "Goal") {
    return null;
  }
  return error("INTENT_GRAPH_CONSTRAIN_INVALID", `constrains edge '${graphEdge.from}' to '${graphEdge.to}' must connect an Invariant node to a Goal node.`, edgeDiagnosticSpan(nodesById, graphEdge, fallbackSpan), {
    edge: graphEdge.kind,
    from: graphEdge.from,
    to: graphEdge.to,
    from_kind: sourceNode?.kind ?? null,
    to_kind: targetNode?.kind ?? null,
    supported_roles: [
      { from_kind: "Invariant", to_kind: "Goal" },
    ],
  });
}

function validateGraphGuardsEdgeRole(nodesById, graphEdge, sourceNode, targetNode, fallbackSpan) {
  const isStepCheck = targetNode?.kind === "Check" && targetNode.data?.scope === "step";
  const isSupportedTarget = targetNode?.kind === "Completion"
    || targetNode?.kind === "Effect"
    || targetNode?.kind === "Checkpoint"
    || targetNode?.kind === "Policy"
    || isStepCheck;
  if (sourceNode?.kind === "Invariant" && isSupportedTarget) {
    return null;
  }
  return error("INTENT_GRAPH_GUARD_ROLE_INVALID", `guards edge '${graphEdge.from}' to '${graphEdge.to}' must connect an Invariant node to a supported guarded node.`, edgeDiagnosticSpan(nodesById, graphEdge, fallbackSpan), {
    edge: graphEdge.kind,
    from: graphEdge.from,
    to: graphEdge.to,
    from_kind: sourceNode?.kind ?? null,
    to_kind: targetNode?.kind ?? null,
    to_scope: targetNode?.data?.scope ?? null,
    supported_roles: [
      { from_kind: "Invariant", to_kind: "Completion" },
      { from_kind: "Invariant", to_kind: "Effect" },
      { from_kind: "Invariant", to_kind: "Checkpoint" },
      { from_kind: "Invariant", to_kind: "Policy" },
      { from_kind: "Invariant", to_kind: "Check", to_scope: "step" },
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
  const targetIsAuthorizationTarget = sourceNode?.kind === "Capability"
    && (targetNode?.kind === "Effect" || targetNode?.kind === "Check" || targetNode?.kind === "Context");
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
      { from_kind: "Capability", to_kind: "Effect" },
      { from_kind: "Capability", to_kind: "Check" },
      { from_kind: "Capability", to_kind: "Context" },
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
  const contractDiagnostic = validateGraphEffectContract(graphNode.data);
  const argsIsObject = isPlainObject(graphNode.data.args);
  const argKindsIsObject = isPlainObject(graphNode.data.argKinds);
  const argSpansIsObject = isPlainObject(graphNode.data.argSpans);
  const argSpansAreValid = argSpansIsObject && Object.values(graphNode.data.argSpans).every(isSpan);
  const approvalRequiredIsBoolean = typeof graphNode.data.approvalRequired === "boolean";
  if (familyIsNonempty && actionIsNonempty && !contractDiagnostic && argsIsObject && argKindsIsObject && argSpansAreValid && approvalRequiredIsBoolean) {
    return null;
  }
  return error("INTENT_GRAPH_EFFECT_INVALID", `effect '${graphNode.label}' must carry valid runtime adapter data.`, graphNode.span ?? graphSpan, {
    effect: graphNode.label,
    effect_id: graphNode.id,
    family: typeof graphNode.data.family === "string" ? graphNode.data.family : null,
    action: typeof graphNode.data.action === "string" ? graphNode.data.action : null,
    family_is_nonempty: familyIsNonempty,
    action_is_nonempty: actionIsNonempty,
    contract_id: typeof graphNode.data.contractId === "string" ? graphNode.data.contractId : null,
    contract_id_is_nonempty: typeof graphNode.data.contractId === "string" && graphNode.data.contractId.trim() !== "",
    contract_is_known: contractDiagnostic ? contractDiagnostic.contract_is_known : true,
    contract_family_matches: contractDiagnostic ? contractDiagnostic.contract_family_matches : true,
    contract_action_matches: contractDiagnostic ? contractDiagnostic.contract_action_matches : true,
    contract_arguments_are_valid: contractDiagnostic ? contractDiagnostic.contract_arguments_are_valid : true,
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
  const contractDiagnostic = validateGraphContextContract(graphNode);
  const argsIsObject = isPlainObject(graphNode.data.args);
  const argKindsIsObject = isPlainObject(graphNode.data.argKinds);
  const argSpansIsObject = isPlainObject(graphNode.data.argSpans);
  const argSpansAreValid = argSpansIsObject && Object.values(graphNode.data.argSpans).every(isSpan);
  if (sourceIsNonempty && expressionIsNonempty && !contractDiagnostic && argsIsObject && argKindsIsObject && argSpansAreValid) {
    return null;
  }
  return error("INTENT_GRAPH_CONTEXT_INVALID", `context '${graphNode.label}' must carry valid runtime source data.`, graphNode.span ?? graphSpan, {
    context: graphNode.label,
    context_id: graphNode.id,
    source: typeof graphNode.data.source === "string" ? graphNode.data.source : null,
    expression: typeof graphNode.data.expression === "string" ? graphNode.data.expression : null,
    source_is_nonempty: sourceIsNonempty,
    expression_is_nonempty: expressionIsNonempty,
    contract_id: typeof graphNode.data.contractId === "string" ? graphNode.data.contractId : null,
    contract_id_is_nonempty: typeof graphNode.data.contractId === "string" && graphNode.data.contractId.trim() !== "",
    contract_is_known: contractDiagnostic ? contractDiagnostic.contract_is_known : true,
    contract_family_matches: contractDiagnostic ? contractDiagnostic.contract_family_matches : true,
    contract_action_matches: contractDiagnostic ? contractDiagnostic.contract_action_matches : true,
    contract_arguments_are_valid: contractDiagnostic ? contractDiagnostic.contract_arguments_are_valid : true,
    args_is_object: argsIsObject,
    arg_kinds_is_object: argKindsIsObject,
    arg_spans_is_object: argSpansIsObject,
    arg_spans_are_valid: argSpansAreValid,
  });
}

function validateGraphContextContract(graphNode) {
  if (graphNode.data.contractId === undefined && graphNode.data.contractArguments === undefined) {
    return null;
  }
  const access = graphContextAccess(graphNode);
  const contractIdIsNonempty = typeof graphNode.data.contractId === "string" && graphNode.data.contractId.trim() !== "";
  const contract = contractIdIsNonempty ? effectContractById(graphNode.data.contractId) : null;
  const contractArgumentsAreValid = validateContractArgumentRefs(contract, {
    args: graphNode.data.args,
    contractArguments: graphNode.data.contractArguments,
  });
  const contractFamilyMatches = Boolean(contract) && Boolean(access) && access.family === contract.family;
  const contractActionMatches = Boolean(contract) && Boolean(access) && access.action === contract.action;
  if (contractIdIsNonempty && contract && contractFamilyMatches && contractActionMatches && contractArgumentsAreValid) {
    return null;
  }
  return {
    contract_id_is_nonempty: contractIdIsNonempty,
    contract_is_known: Boolean(contract),
    contract_family_matches: contractFamilyMatches,
    contract_action_matches: contractActionMatches,
    contract_arguments_are_valid: contractArgumentsAreValid,
  };
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
  const effectContractDiagnostic = !effectIsPresent || !effectIsObject ? null : validateGraphEffectContract(effect);
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
    && !effectContractDiagnostic
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
    effect_contract_id: typeof effect.contractId === "string" ? effect.contractId : null,
    effect_contract_id_is_nonempty: !effectIsPresent || (typeof effect.contractId === "string" && effect.contractId.trim() !== ""),
    effect_contract_is_known: effectContractDiagnostic ? effectContractDiagnostic.contract_is_known : true,
    effect_contract_family_matches: effectContractDiagnostic ? effectContractDiagnostic.contract_family_matches : true,
    effect_contract_action_matches: effectContractDiagnostic ? effectContractDiagnostic.contract_action_matches : true,
    effect_contract_arguments_are_valid: effectContractDiagnostic ? effectContractDiagnostic.contract_arguments_are_valid : true,
    effect_args_is_object: effectArgsIsObject,
    effect_arg_kinds_is_object: effectArgKindsIsObject,
    effect_arg_spans_is_object: effectArgSpansIsObject,
    effect_arg_spans_are_valid: effectArgSpansAreValid,
  });
}

function validateGraphEffectContract(effectData) {
  if (effectData.contractId === undefined && effectData.contractArguments === undefined) {
    return null;
  }
  const contractIdIsNonempty = typeof effectData.contractId === "string" && effectData.contractId.trim() !== "";
  const contract = contractIdIsNonempty ? effectContractById(effectData.contractId) : null;
  const contractArgumentsAreValid = validateContractArgumentRefs(contract, effectData);
  const contractFamilyMatches = Boolean(contract) && effectData.family === contract.family;
  const contractActionMatches = Boolean(contract) && effectData.action === contract.action;
  if (contractIdIsNonempty && contract && contractFamilyMatches && contractActionMatches && contractArgumentsAreValid) {
    return null;
  }
  return {
    contract_id_is_nonempty: contractIdIsNonempty,
    contract_is_known: Boolean(contract),
    contract_family_matches: contractFamilyMatches,
    contract_action_matches: contractActionMatches,
    contract_arguments_are_valid: contractArgumentsAreValid,
  };
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

function contextContractAccess(context) {
  if (context.source !== "web" && context.source !== "documents") {
    return null;
  }
  return contextAccess(context);
}

function invalidGraphGrantAuthorization(capabilityNode, targetNode, graphEdge) {
  const capability = graphCapabilityAccess(capabilityNode);
  const access = graphAuthorizationAccess(targetNode);
  if (!capability || !access) {
    return null;
  }
  if (effectArguments(access).length === 0) {
    return null;
  }
  if (!isFamilyMatch(access.family, capability.family)) {
    return {
      from: graphEdge.from,
      to: graphEdge.to,
      reason: "family_mismatch",
      capability_family: capability.family,
      target_family: access.family,
      target_action: access.action,
      argument: null,
      value: null,
      allowed: [],
    };
  }

  const denial = getCapabilityDenial(access, [capability]);
  if (!denial) {
    const contractDenial = getAuthorizationContractDenial(access, capability, graphEdge);
    if (!contractDenial) {
      return null;
    }
    return {
      from: graphEdge.from,
      to: graphEdge.to,
      reason: contractDenial.reason,
      capability_family: capability.family,
      target_family: access.family,
      target_action: access.action,
      argument: contractDenial.argument,
      value: contractDenial.value,
      allowed: contractDenial.allowed,
    };
  }
  return {
    from: graphEdge.from,
    to: graphEdge.to,
    reason: "grant_mismatch",
    capability_family: capability.family,
    target_family: access.family,
    target_action: access.action,
    argument: denial.argument,
    value: denial.value,
    allowed: denial.allowed,
  };
}

function getAuthorizationContractDenial(access, capability, graphEdge) {
  const edgeData = isPlainObject(graphEdge.data) ? graphEdge.data : null;
  if (access.contractId && !edgeData) {
    return {
      reason: "edge_metadata_missing",
      argument: null,
      value: null,
      allowed: [access.contractId],
    };
  }
  if (access.contractId && edgeData.contractId !== access.contractId) {
    return {
      reason: "edge_contract_mismatch",
      argument: null,
      value: typeof edgeData.contractId === "string" ? edgeData.contractId : null,
      allowed: [access.contractId],
    };
  }
  if (access.contractId && !contractArgumentsEqual(edgeData.contractArguments, access.contractArguments ?? {})) {
    return {
      reason: "edge_contract_arguments_mismatch",
      argument: null,
      value: isPlainObject(edgeData.contractArguments) ? edgeData.contractArguments : null,
      allowed: [access.contractArguments ?? {}],
    };
  }
  const expectedArguments = effectArguments(access);
  const edgeGrants = Array.isArray(edgeData?.grants) ? edgeData.grants : [];
  for (const argument of expectedArguments) {
    const matchedGrant = (capability.grants ?? []).find((grant) => {
      return grant.action === access.action
        && grantArgumentForEffectArgument(argument, grant)
        && isGrantMatch(argument, grant);
    });
    if (!matchedGrant) continue;
    if (access.contractId && matchedGrant.contractId && matchedGrant.contractId !== access.contractId) {
      return {
        reason: "grant_contract_mismatch",
        argument: argument.key,
        value: matchedGrant.contractId,
        allowed: [access.contractId],
      };
    }
    const edgeGrant = edgeGrants.find((grant) => grant.argument === argument.key);
    const expectedSourceArgument = access.contractArguments?.[argument.key] ?? argument.key;
    if (edgeGrant && edgeGrant.sourceArgument !== expectedSourceArgument) {
      return {
        reason: "edge_argument_mismatch",
        argument: argument.key,
        value: edgeGrant.sourceArgument,
        allowed: [expectedSourceArgument],
      };
    }
    if (access.contractId && !edgeGrant) {
      return {
        reason: "edge_grant_missing",
        argument: argument.key,
        value: null,
        allowed: [authorizationGrantRecord(argument, matchedGrant, expectedSourceArgument)],
      };
    }
    const expectedEdgeGrant = authorizationGrantRecord(argument, matchedGrant, expectedSourceArgument);
    if (access.contractId && !authorizationGrantRecordsEqual(edgeGrant, expectedEdgeGrant)) {
      return {
        reason: "edge_grant_mismatch",
        argument: argument.key,
        value: edgeGrant ?? null,
        allowed: [expectedEdgeGrant],
      };
    }
  }
  const expectedArgumentKeys = new Set(expectedArguments.map((argument) => argument.key));
  const extraEdgeGrant = edgeGrants.find((edgeGrant) => !expectedArgumentKeys.has(edgeGrant.argument));
  if (access.contractId && extraEdgeGrant) {
    return {
      reason: "edge_grant_extra",
      argument: typeof extraEdgeGrant.argument === "string" ? extraEdgeGrant.argument : null,
      value: extraEdgeGrant,
      allowed: [...expectedArgumentKeys],
    };
  }
  return null;
}

function contractArgumentsEqual(left, right) {
  if (!isPlainObject(left) || !isPlainObject(right)) {
    return false;
  }
  const leftEntries = Object.entries(left);
  const rightEntries = Object.entries(right);
  return leftEntries.length === rightEntries.length
    && leftEntries.every(([key, value]) => right[key] === value);
}

function authorizationGrantRecord(argument, grant, sourceArgument) {
  const grantArgument = grantArgumentForEffectArgument(argument, grant) ?? grant;
  return {
    argument: argument.key,
    sourceArgument,
    value: argument.value,
    grantAction: grant.action,
    grantKey: grantArgument.key,
    grantValue: grantArgument.value,
    grantApprovalRequired: Boolean(grant.approvalRequired),
    grantSpan: grant.span,
    grantActionSpan: grant.actionSpan,
    grantArgumentSpan: grantArgument.span ?? grant.span,
    grantKeySpan: grantArgument.keySpan ?? null,
    grantValueSpan: grantArgument.valueSpan ?? null,
    grantArgs: Array.isArray(grant.args) ? grant.args : [],
  };
}

function authorizationGrantRecordsEqual(left, right) {
  return isPlainObject(left)
    && left.argument === right.argument
    && left.sourceArgument === right.sourceArgument
    && left.value === right.value
    && left.grantAction === right.grantAction
    && left.grantKey === right.grantKey
    && grantValuesEqual(left.grantValue, right.grantValue)
    && left.grantApprovalRequired === right.grantApprovalRequired
    && spansEqual(left.grantSpan, right.grantSpan)
    && spansEqual(left.grantActionSpan, right.grantActionSpan)
    && spansEqual(left.grantArgumentSpan, right.grantArgumentSpan)
    && nullableSpansEqual(left.grantKeySpan, right.grantKeySpan)
    && nullableSpansEqual(left.grantValueSpan, right.grantValueSpan)
    && grantArgumentRecordsEqual(left.grantArgs, right.grantArgs);
}

function grantValuesEqual(left, right) {
  if (Array.isArray(left) || Array.isArray(right)) {
    return Array.isArray(left)
      && Array.isArray(right)
      && left.length === right.length
      && left.every((value, index) => value === right[index]);
  }
  return left === right;
}

function nullableSpansEqual(left, right) {
  if (left === null || right === null) {
    return left === right;
  }
  return spansEqual(left, right);
}

function grantArgumentRecordsEqual(left, right) {
  if (!Array.isArray(left) || !Array.isArray(right) || left.length !== right.length) {
    return false;
  }
  return left.every((argument, index) => {
    const expected = right[index];
    return isPlainObject(argument)
      && isPlainObject(expected)
      && argument.key === expected.key
      && argument.kind === expected.kind
      && grantValuesEqual(argument.value, expected.value)
      && nullableSpansEqual(argument.keySpan ?? null, expected.keySpan ?? null)
      && spansEqual(argument.valueSpan, expected.valueSpan)
      && spansEqual(argument.span, expected.span);
  });
}

function graphCapabilityAccess(capabilityNode) {
  if (
    capabilityNode?.kind !== "Capability"
    || typeof capabilityNode.data?.family !== "string"
    || capabilityNode.data.family.trim() === ""
    || !Array.isArray(capabilityNode.data.grants)
    || !capabilityNode.data.grants.every((grant) => isGraphGrantRecord(grant, capabilityNode.data.family))
  ) {
    return null;
  }
  return {
    family: capabilityNode.data.family,
    grants: capabilityNode.data.grants,
  };
}

function graphAuthorizationAccess(graphNode) {
  if (graphNode.kind === "Effect") {
    return graphEffectAccess(graphNode, graphNode.data);
  }
  if (graphNode.kind === "Check" && graphNode.data?.effect) {
    return graphEffectAccess(graphNode, graphNode.data.effect);
  }
  if (graphNode.kind === "Context" && requiresContextAuthorization(graphNode)) {
    return graphContextAccess(graphNode);
  }
  return null;
}

function graphContextAccess(graphNode) {
  if (
    typeof graphNode.data.expression !== "string"
    || !isPlainObject(graphNode.data.args)
    || !isPlainObject(graphNode.data.argKinds)
    || !isPlainObject(graphNode.data.argSpans)
    || !Object.values(graphNode.data.args).every((value) => typeof value === "string")
  ) {
    return null;
  }
  const access = contextAccess({
    source: graphNode.data.source,
    args: graphNode.data.args,
    argKinds: graphNode.data.argKinds,
    argSpans: graphNode.data.argSpans,
    expression: graphNode.data.expression,
    span: graphNode.span,
  });
  if (!access) return null;
  return {
    ...access,
    contractId: graphNode.data.contractId ?? access.contractId,
    contractArguments: graphNode.data.contractArguments ?? access.contractArguments,
  };
}

function graphEffectAccess(graphNode, effectData) {
  if (
    typeof effectData?.family !== "string"
    || effectData.family.trim() === ""
    || typeof effectData.action !== "string"
    || effectData.action.trim() === ""
    || !isPlainObject(effectData.args)
    || !isPlainObject(effectData.argKinds)
    || !isPlainObject(effectData.argSpans)
    || !Object.values(effectData.args).every((value) => typeof value === "string")
  ) {
    return null;
  }
  return {
    kind: "EffectUse",
    name: graphNode.label,
    family: effectData.family,
    action: effectData.action,
    contractId: effectData.contractId ?? null,
    contractArguments: effectData.contractArguments ?? {},
    args: effectData.args,
    argKinds: effectData.argKinds,
    argSpans: effectData.argSpans,
    expression: effectData.expression ?? graphNode.label,
    span: graphNode.span,
  };
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
    return validateGraphContextInformsMetadata(ownerGoalInformsEdges[0], graphNode, ownerGoal, fallbackSpan);
  }
  return error("INTENT_GRAPH_CONTEXT_INFORMS_INVALID", `context '${graphNode.label}' must inform its owning goal.`, graphNode.span ?? fallbackSpan, {
    context: graphNode.label,
    context_id: graphNode.id,
    owner_goal_id: ownerGoalId,
    informs_edges: informsEdges.length,
    owner_goal_informs_edges: ownerGoalInformsEdges.length,
  });
}

function validateGraphContextInformsMetadata(graphEdge, contextNode, goalNode, fallbackSpan) {
  const data = graphEdge.data;
  const dataIsObject = isPlainObject(data);
  const sourceMatchesContext = dataIsObject && data.source === contextNode.data?.source;
  const expressionMatchesContext = dataIsObject && data.expression === contextNode.data?.expression;
  const argsMatchContext = dataIsObject && stringMapsEqual(data.args, contextNode.data?.args ?? {});
  const argKindsMatchContext = dataIsObject && stringMapsEqual(data.argKinds, contextNode.data?.argKinds ?? {});
  const argSpansMatchContext = dataIsObject && spanMapsEqual(data.argSpans, contextNode.data?.argSpans ?? {});
  const trustMatchesContext = dataIsObject && trustRecordsEqual(data.trust, contextNode.data?.trust);
  const contractIdMatchesContext = dataIsObject && (data.contractId ?? null) === (contextNode.data?.contractId ?? null);
  const contractArgumentsMatchContext = dataIsObject && contractArgumentsEqual(data.contractArguments, contextNode.data?.contractArguments ?? {});
  const sourceSpanMatchesContext = dataIsObject && spansEqual(data.sourceSpan, contextNode.span);
  const targetSpanMatchesGoal = dataIsObject && spansEqual(data.targetSpan, goalNode.span);
  if (
    dataIsObject
    && sourceMatchesContext
    && expressionMatchesContext
    && argsMatchContext
    && argKindsMatchContext
    && argSpansMatchContext
    && trustMatchesContext
    && contractIdMatchesContext
    && contractArgumentsMatchContext
    && sourceSpanMatchesContext
    && targetSpanMatchesGoal
  ) {
    return null;
  }
  return error("INTENT_GRAPH_CONTEXT_INFORMS_INVALID", `informs edge '${graphEdge.from}' to '${graphEdge.to}' must carry context metadata matching its source context and owning goal.`, edgeDiagnosticSpan(new Map([[contextNode.id, contextNode], [goalNode.id, goalNode]]), graphEdge, fallbackSpan), {
    context: contextNode.label,
    context_id: contextNode.id,
    owner_goal_id: goalNode.id,
    informs_edges: 1,
    owner_goal_informs_edges: 1,
    data_is_object: dataIsObject,
    source_matches_context: sourceMatchesContext,
    expression_matches_context: expressionMatchesContext,
    args_match_context: argsMatchContext,
    arg_kinds_match_context: argKindsMatchContext,
    arg_spans_match_context: argSpansMatchContext,
    trust_matches_context: trustMatchesContext,
    contract_id_matches_context: contractIdMatchesContext,
    contract_arguments_match_context: contractArgumentsMatchContext,
    source_span_matches_context: sourceSpanMatchesContext,
    target_span_matches_goal: targetSpanMatchesGoal,
  });
}

function validateGraphStepPlanMetadata(graphEdge, goalNode, stepNode, stepIndex, fallbackSpan) {
  const data = graphEdge.data;
  const dataIsObject = isPlainObject(data);
  const goalMatchesSource = dataIsObject && data.goal === goalNode.label;
  const stepMatchesTarget = dataIsObject && data.step === stepNode.label;
  const indexMatchesTarget = dataIsObject && data.index === stepIndex;
  const sourceSpanMatchesGoal = dataIsObject && spansEqual(data.sourceSpan, goalNode.span);
  const targetSpanMatchesStep = dataIsObject && spansEqual(data.targetSpan, stepNode.span);
  if (
    dataIsObject
    && goalMatchesSource
    && stepMatchesTarget
    && indexMatchesTarget
    && sourceSpanMatchesGoal
    && targetSpanMatchesStep
  ) {
    return null;
  }
  return error("INTENT_GRAPH_STEP_PLAN_INVALID", `plans edge '${graphEdge.from}' to '${graphEdge.to}' must carry step plan metadata matching its owning goal and target step.`, edgeDiagnosticSpan(new Map([[goalNode.id, goalNode], [stepNode.id, stepNode]]), graphEdge, fallbackSpan), {
    step: stepNode.label,
    step_id: stepNode.id,
    owner_goal_id: goalNode.id,
    plans_edges: 1,
    owner_goal_plans_edges: 1,
    plan_edge: { from: graphEdge.from, to: graphEdge.to, kind: graphEdge.kind },
    data_is_object: dataIsObject,
    goal_matches_source: goalMatchesSource,
    step_matches_target: stepMatchesTarget,
    index_matches_target: indexMatchesTarget,
    source_span_matches_goal: sourceSpanMatchesGoal,
    target_span_matches_step: targetSpanMatchesStep,
  });
}

function validateGraphStepPrecedesMetadata(graphEdge, previousStepNode, nextStepNode, previousIndex, nextIndex) {
  const data = graphEdge.data;
  const dataIsObject = isPlainObject(data);
  return {
    edge: { from: graphEdge.from, to: graphEdge.to },
    data_is_object: dataIsObject,
    previous_step_matches_source: dataIsObject && data.previousStep === previousStepNode.label,
    next_step_matches_target: dataIsObject && data.nextStep === nextStepNode.label,
    previous_index_matches_source: dataIsObject && data.previousIndex === previousIndex,
    next_index_matches_target: dataIsObject && data.nextIndex === nextIndex,
    source_span_matches_previous_step: dataIsObject && spansEqual(data.sourceSpan, previousStepNode.span),
    target_span_matches_next_step: dataIsObject && spansEqual(data.targetSpan, nextStepNode.span),
  };
}

function validateGraphTypeDeclareMetadata(graphEdge, typeNode, goalNode) {
  const data = graphEdge.data;
  const dataIsObject = isPlainObject(data);
  return {
    edge: { from: graphEdge.from, to: graphEdge.to },
    data_is_object: dataIsObject,
    type_matches_source: dataIsObject && data.type === typeNode.label,
    definition_matches_source: dataIsObject && (data.definition ?? null) === (typeNode.data?.definition ?? null),
    goal_matches_target: dataIsObject && data.goal === goalNode.label,
    source_span_matches_type: dataIsObject && spansEqual(data.sourceSpan, typeNode.span),
    target_span_matches_goal: dataIsObject && spansEqual(data.targetSpan, goalNode.span),
  };
}

function typeDeclareMetadataIsValid(metadata) {
  return metadata.data_is_object
    && metadata.type_matches_source
    && metadata.definition_matches_source
    && metadata.goal_matches_target
    && metadata.source_span_matches_type
    && metadata.target_span_matches_goal;
}

function validateGraphMemoryDeclareMetadata(graphEdge, goalNode, memoryNode, fallbackSpan) {
  const data = graphEdge.data;
  const dataIsObject = isPlainObject(data);
  const goalMatchesSource = dataIsObject && data.goal === goalNode.label;
  const memoryMatchesTarget = dataIsObject && data.memory === memoryNode.label;
  const memoryScopeMatchesTarget = dataIsObject && data.memoryScope === memoryNode.data?.scope;
  const sourceSpanMatchesGoal = dataIsObject && spansEqual(data.sourceSpan, goalNode.span);
  const targetSpanMatchesMemory = dataIsObject && spansEqual(data.targetSpan, memoryNode.span);
  if (
    dataIsObject
    && goalMatchesSource
    && memoryMatchesTarget
    && memoryScopeMatchesTarget
    && sourceSpanMatchesGoal
    && targetSpanMatchesMemory
  ) {
    return null;
  }
  return error("INTENT_GRAPH_MEMORY_DECLARE_INVALID", `declares edge '${graphEdge.from}' to '${graphEdge.to}' must carry memory ownership metadata matching its owning goal and target memory.`, edgeDiagnosticSpan(new Map([[goalNode.id, goalNode], [memoryNode.id, memoryNode]]), graphEdge, fallbackSpan), {
    memory: memoryNode.label,
    memory_id: memoryNode.id,
    owner_goal_id: goalNode.id,
    declares_edges: 1,
    owner_goal_declares_edges: 1,
    wrong_goal_declares_edges: 0,
    declare_edge: { from: graphEdge.from, to: graphEdge.to, kind: graphEdge.kind },
    data_is_object: dataIsObject,
    goal_matches_source: goalMatchesSource,
    memory_matches_target: memoryMatchesTarget,
    memory_scope_matches_target: memoryScopeMatchesTarget,
    source_span_matches_goal: sourceSpanMatchesGoal,
    target_span_matches_memory: targetSpanMatchesMemory,
  });
}

function validateGraphCapabilityOwnerAuthorizationMetadata(graphEdge, capabilityNode, goalNode, fallbackSpan) {
  const data = graphEdge.data;
  const dataIsObject = isPlainObject(data);
  const capabilityMatchesSource = dataIsObject && data.capability === capabilityNode.label;
  const familyMatchesSource = dataIsObject && data.family === capabilityNode.data?.family;
  const actionMatchesSource = dataIsObject && (data.action ?? null) === (capabilityNode.data?.action ?? null);
  const approvalPolicyMatchesSource = dataIsObject && data.approvalPolicy === capabilityNode.data?.approvalPolicy;
  const goalMatchesTarget = dataIsObject && data.goal === goalNode.label;
  const sourceSpanMatchesCapability = dataIsObject && spansEqual(data.sourceSpan, capabilityNode.span);
  const targetSpanMatchesGoal = dataIsObject && spansEqual(data.targetSpan, goalNode.span);
  if (
    dataIsObject
    && capabilityMatchesSource
    && familyMatchesSource
    && actionMatchesSource
    && approvalPolicyMatchesSource
    && goalMatchesTarget
    && sourceSpanMatchesCapability
    && targetSpanMatchesGoal
  ) {
    return null;
  }
  return error("INTENT_GRAPH_CAPABILITY_AUTHORIZES_INVALID", `authorizes edge '${graphEdge.from}' to '${graphEdge.to}' must carry capability ownership metadata matching its source capability and owning goal.`, edgeDiagnosticSpan(new Map([[capabilityNode.id, capabilityNode], [goalNode.id, goalNode]]), graphEdge, fallbackSpan), {
    capability: capabilityNode.label,
    capability_id: capabilityNode.id,
    owner_goal_id: goalNode.id,
    authorizes_edges: 1,
    owner_goal_authorizes_edges: 1,
    wrong_goal_authorizes_edges: 0,
    authorization_edge: { from: graphEdge.from, to: graphEdge.to, kind: graphEdge.kind },
    data_is_object: dataIsObject,
    capability_matches_source: capabilityMatchesSource,
    family_matches_source: familyMatchesSource,
    action_matches_source: actionMatchesSource,
    approval_policy_matches_source: approvalPolicyMatchesSource,
    goal_matches_target: goalMatchesTarget,
    source_span_matches_capability: sourceSpanMatchesCapability,
    target_span_matches_goal: targetSpanMatchesGoal,
  });
}

function stepPrecedesMetadataIsValid(metadata) {
  return metadata.data_is_object
    && metadata.previous_step_matches_source
    && metadata.next_step_matches_target
    && metadata.previous_index_matches_source
    && metadata.next_index_matches_target
    && metadata.source_span_matches_previous_step
    && metadata.target_span_matches_next_step;
}

function trustRecordsEqual(left, right) {
  return isPlainObject(left)
    && isPlainObject(right)
    && left.zone === right.zone
    && left.source === right.source
    && (left.argument ?? null) === (right.argument ?? null);
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

function validateGoalStepSequence(graphNodes, graphEdges, incomingEdgesByNode, goalNode, fallbackSpan) {
  const stepNodes = graphNodes.filter((candidate) => candidate.kind === "Step" && candidate.id.startsWith(`${goalNode.id}:step:`));
  if (stepNodes.length === 0) {
    return null;
  }

  const stepIds = new Set(stepNodes.map((stepNode) => stepNode.id));
  const incomingPrecedesCounts = new Map(stepNodes.map((stepNode) => [stepNode.id, 0]));
  const outgoingPrecedesTargets = new Map(stepNodes.map((stepNode) => [stepNode.id, []]));
  const precedesEdges = [];
  const malformedPrecedesEdges = [];
  const unorderedPrecedesEdges = [];
  const invalidPrecedesMetadata = [];

  for (const graphEdge of graphEdges) {
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
    const previousStepNode = graphNodes.find((candidate) => candidate.id === graphEdge.from);
    const nextStepNode = graphNodes.find((candidate) => candidate.id === graphEdge.to);
    const previousIndex = graphStepIndex(graphNodes, goalNode.id, graphEdge.from);
    const nextIndex = graphStepIndex(graphNodes, goalNode.id, graphEdge.to);
    const metadata = validateGraphStepPrecedesMetadata(graphEdge, previousStepNode, nextStepNode, previousIndex, nextIndex);
    if (!stepPrecedesMetadataIsValid(metadata)) {
      invalidPrecedesMetadata.push(metadata);
    }
    if (nextIndex !== previousIndex + 1) {
      unorderedPrecedesEdges.push({ from: graphEdge.from, to: graphEdge.to, previous_index: previousIndex, next_index: nextIndex });
    }
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
      && orderedStepIds.length === stepNodes.length
      && unorderedPrecedesEdges.length === 0
      && invalidPrecedesMetadata.length === 0;

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
    unordered_precedes_edges: unorderedPrecedesEdges,
    invalid_precedes_metadata: invalidPrecedesMetadata,
    ordered_step_ids: orderedStepIds,
    completion_producer_step_ids: completionProducerStepIds,
    expected_completion_producer_step_id: expectedTailStepId,
  });
}

function graphStepIndex(graphNodes, goalId, stepId) {
  return graphNodes
    .filter((candidate) => candidate.kind === "Step" && candidate.id.startsWith(`${goalId}:step:`))
    .findIndex((candidate) => candidate.id === stepId);
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
  if (!isPlainObject(graphEdge)) {
    return fallbackSpan;
  }
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

function parseCapabilityGrant(capabilityName, text, grantSpan, file = grantSpan?.file ?? null, lineNumber = grantSpan?.start?.line ?? 1, raw = text) {
  const trimmed = text.trim();
  const family = capabilityFamily(capabilityName);
  const lineGrant = parseCapabilityLineGrant(family, trimmed, grantSpan, file, lineNumber, raw);
  if (lineGrant) {
    return lineGrant;
  }

  const dottedCall = trimmed.match(/^([a-z][a-z0-9_]*)\.([a-z][a-z0-9_]*)\((.*)\)$/);
  if (dottedCall) {
    const parsedArgs = parseCallArgs(trimmed, file, lineNumber, raw);
    const action = canonicalGrantAction(family, dottedCall[2], `${dottedCall[1]}.${dottedCall[2]}`);
    const args = parsedArgs.records.map((argument) => canonicalGrantArgument(family, action, argument));
    if (args.length > 0) {
      return capabilityGrantRecord(family, action, args, trimmed, grantSpan, grantActionSpan(trimmed, dottedCall[2], file, lineNumber, raw));
    }
  }

  return null;
}

function parseCapabilityLineGrant(family, trimmed, grantSpan, file, lineNumber, raw) {
  const action = /^([a-z][a-z0-9_]*)\b/.exec(trimmed)?.[1] ?? null;
  if (!action) {
    return null;
  }
  const argsText = trimmed.slice(action.length);
  if (!argsText.trim()) {
    return null;
  }
  const canonicalAction = canonicalGrantAction(family, action);
  const args = parseGrantLineArguments(argsText, action.length, file, lineNumber, raw, trimmed)
    .map((argument) => canonicalGrantArgument(family, canonicalAction, argument));
  if (args.length === 0) {
    return null;
  }
  return capabilityGrantRecord(family, canonicalAction, args, trimmed, grantSpan, grantActionSpan(trimmed, action, file, lineNumber, raw));
}

function parseGrantLineArguments(argsText, trimmedOffset, file, lineNumber, raw, trimmed) {
  const args = [];
  let index = 0;
  while (index < argsText.length) {
    const leading = argsText.slice(index).search(/\S/);
    if (leading < 0) {
      break;
    }
    const keyStartInArgs = index + leading;
    const keyMatch = /^([a-z][a-z0-9_]*)\s*:/.exec(argsText.slice(keyStartInArgs));
    if (!keyMatch) {
      return [];
    }
    const sourceKey = keyMatch[1];
    const colonInArgs = keyStartInArgs + keyMatch[0].lastIndexOf(":");
    const valueLeading = argsText.slice(colonInArgs + 1).search(/\S/);
    if (valueLeading < 0) {
      return [];
    }
    const valueStartInArgs = colonInArgs + 1 + valueLeading;
    const valueEndInArgs = grantLineValueEnd(argsText, valueStartInArgs);
    const valueText = argsText.slice(valueStartInArgs, valueEndInArgs).trim();
    if (!valueText) {
      return [];
    }
    const parsed = parseCallArgumentValue(valueText, file, lineNumber, raw);
    const keyStart = trimmedOffset + keyStartInArgs;
    const valueStart = trimmedOffset + valueStartInArgs;
    args.push({
      key: sourceKey,
      value: parsed.value,
      kind: parsed.kind,
      keySpan: sourceSpan(file, lineNumber, raw, trimmed, keyStart, sourceKey.length),
      valueSpan: sourceSpan(file, lineNumber, raw, trimmed, valueStart, valueText.length),
      span: sourceSpan(file, lineNumber, raw, trimmed, keyStart, valueStart + valueText.length - keyStart),
    });
    index = valueEndInArgs;
  }
  return args;
}

function grantLineValueEnd(text, valueStart) {
  let inString = false;
  let bracketDepth = 0;
  for (let index = valueStart; index < text.length; index += 1) {
    const char = text[index];
    if (char === "\"") {
      inString = !inString;
      continue;
    }
    if (inString) {
      continue;
    }
    if (char === "[") {
      bracketDepth += 1;
      continue;
    }
    if (char === "]") {
      bracketDepth = Math.max(0, bracketDepth - 1);
      continue;
    }
    if (bracketDepth === 0 && /\s/.test(char)) {
      const rest = text.slice(index);
      if (/^\s+[a-z][a-z0-9_]*\s*:/.test(rest) || rest.trim() === "") {
        return index;
      }
    }
  }
  return text.length;
}

function capabilityGrantRecord(family, action, args, raw, grantSpan, actionSpan) {
  const [firstArg] = args;
  const contract = effectContractForGrant({ family, action, key: firstArg.key });
  const approvalRequired = args.some((argument) => {
    return argument.key === "approval" && argument.value === "required";
  });
  return {
    action,
    key: firstArg.key,
    value: firstArg.value,
    args,
    approvalRequired,
    raw,
    span: grantSpan,
    actionSpan,
    ...(contract ? { contractId: contract.id, contractArgument: firstArg.key } : {}),
  };
}

function canonicalGrantArgument(family, action, argument) {
  const contractArgument = effectContractArgumentForGrant({ family, action, key: argument.key });
  return {
    ...argument,
    key: contractArgument?.argument.key ?? argument.key,
  };
}

function canonicalGrantAction(family, action, sourceName = `${family}.${action}`) {
  return effectContractByName(sourceName)?.action ?? action;
}

function grantActionSpan(trimmed, action, file, lineNumber, raw) {
  return sourceSpan(file, lineNumber, raw, trimmed, trimmed.indexOf(action), action.length);
}

function sourceSpan(file, lineNumber, raw, trimmed, trimmedStart, length) {
  const rawTrimmedStart = raw.indexOf(trimmed);
  const startIndex = (rawTrimmedStart >= 0 ? rawTrimmedStart : 0) + trimmedStart;
  return span(file, lineNumber, startIndex + 1, lineNumber, startIndex + length + 1);
}

function hasApprovalRequired(lines) {
  return lines.some((line) => /^approval\s+required$/.test(line.text) || /^approval\s*:\s*required$/.test(line.text));
}

function parseCallArgs(text, file = null, lineNumber = 1, raw = text) {
  const values = {};
  const kinds = {};
  const spans = {};
  const records = [];
  const envelope = callArgsEnvelope(text, file, lineNumber, raw);
  if (!envelope.text.trim()) {
    return { values, kinds, spans, records };
  }
  let positionalIndex = 0;
  for (const argument of splitCallArguments(envelope.text, envelope.startIndex, file, lineNumber, raw)) {
    const trimmed = argument.text.trim();
    if (!trimmed) {
      throw parseError(file, lineNumber, raw, "empty call argument");
    }
    const argumentLeading = argument.text.indexOf(trimmed);
    const argumentIndex = argument.startIndex + argumentLeading;
    const named = /^([a-z][a-z0-9_]*)\s*:/.exec(trimmed);
    const colonIndex = named ? trimmed.indexOf(":") : -1;
    const key = named ? named[1] : `_${positionalIndex}`;
    const valueSource = named ? trimmed.slice(colonIndex + 1) : trimmed;
    const valueLeading = valueSource.search(/\S/);
    const valueText = valueLeading >= 0 ? valueSource.slice(valueLeading).trim() : "";
    const valueIndex = named ? argumentIndex + colonIndex + 1 + valueLeading : argumentIndex;
    const parsed = parseCallArgumentValue(valueText, file, lineNumber, raw);
    values[key] = parsed.value;
    kinds[key] = parsed.kind;
    const spanStart = named ? argumentIndex : valueIndex;
    const spanText = named ? trimmed : valueText;
    const argumentSpan = callArgSpan(file, lineNumber, raw, spanStart, spanText);
    if (argumentSpan) spans[key] = argumentSpan;
    records.push({
      key,
      value: parsed.value,
      kind: parsed.kind,
      keySpan: named ? callArgSpan(file, lineNumber, raw, argumentIndex, key) : null,
      valueSpan: callArgSpan(file, lineNumber, raw, valueIndex, valueText),
      span: argumentSpan,
    });
    if (!named) {
      positionalIndex += 1;
    }
  }
  return { values, kinds, spans, records };
}

function callArgsEnvelope(text, file, lineNumber, raw) {
  const openIndex = text.indexOf("(");
  if (openIndex === -1) {
    if (!/[,:"]/.test(text)) {
      return { text: "", startIndex: 0 };
    }
    return { text, startIndex: 0 };
  }
  const closeIndex = text.lastIndexOf(")");
  if (closeIndex < openIndex) {
    throw parseError(file, lineNumber, raw, `unterminated call expression '${text}'`);
  }
  if (text.slice(closeIndex + 1).trim() !== "") {
    throw parseError(file, lineNumber, raw, `unsupported call expression '${text}'`);
  }
  return { text: text.slice(openIndex + 1, closeIndex), startIndex: openIndex + 1 };
}

function splitCallArguments(text, startIndex, file, lineNumber, raw) {
  const args = [];
  let inString = false;
  let bracketDepth = 0;
  let partStart = 0;
  for (let index = 0; index < text.length; index += 1) {
    const char = text[index];
    if (char === "\"") {
      inString = !inString;
      continue;
    }
    if (inString) {
      continue;
    }
    if (char === "[") {
      bracketDepth += 1;
      continue;
    }
    if (char === "]") {
      bracketDepth = Math.max(0, bracketDepth - 1);
      continue;
    }
    if (bracketDepth === 0 && char === ",") {
      args.push({ text: text.slice(partStart, index), startIndex: startIndex + partStart });
      partStart = index + 1;
    }
  }
  if (inString) {
    throw parseError(file, lineNumber, raw, "unterminated string literal in call argument");
  }
  args.push({ text: text.slice(partStart), startIndex: startIndex + partStart });
  return args;
}

function parseCallArgumentValue(value, file, lineNumber, raw) {
  const stringLiteral = /^"([^"]*)"$/.exec(value);
  if (stringLiteral) {
    return { kind: "string", value: stringLiteral[1] };
  }
  const stringList = /^\[(.*)\]$/.exec(value);
  if (stringList) {
    const items = splitCallArguments(stringList[1], 1, file, lineNumber, raw).map((item) => item.text.trim());
    const values = items.length === 1 && items[0] === ""
      ? []
      : items.map((item) => {
        const parsed = /^"([^"]*)"$/.exec(item);
        if (!parsed) {
          throw parseError(file, lineNumber, raw, `unsupported list argument '${value}'`);
        }
        return parsed[1];
      });
    return { kind: "string_list", value: values };
  }
  const integerLiteral = /^[0-9]+$/.exec(value);
  if (integerLiteral) {
    return { kind: "integer", value: Number(value) };
  }
  const durationLiteral = /^[0-9]+(?:ms|s|m|h|d)$/.exec(value);
  if (durationLiteral) {
    return { kind: "duration", value };
  }
  if (/^[a-z][a-z0-9_]*$/.test(value)) {
    return { kind: "identifier", value };
  }
  throw parseError(file, lineNumber, raw, `unsupported call argument '${value}'`);
}

function callArgSpan(file, lineNumber, raw, textIndex, fallbackText) {
  if (!file) {
    return null;
  }
  const rawIndex = raw.indexOf(fallbackText, textIndex);
  const startIndex = rawIndex >= 0 ? rawIndex : textIndex;
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

function verificationImpureEffect(requirement, capabilities = []) {
  for (const match of requirement.value.matchAll(/\b([A-Za-z][A-Za-z0-9_.]*)\s*\(([^)]*)\)/g)) {
    const name = match[1];
    if (name === "shell") {
      continue;
    }
    if (!isKnownEffectCall(name) && !isDeclaredCapabilityCall(name, capabilities)) {
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

function isDeclaredCapabilityCall(name, capabilities) {
  if (!name.includes(".")) {
    return false;
  }
  const family = effectFamily(name);
  return capabilities.some((capability) => isFamilyMatch(family, capability.family));
}

function requirementValueSpan(requirement, startIndex, length) {
  const startColumn = requirement.span.start.column + "require ".length + startIndex;
  return span(requirement.span.file, requirement.span.start.line, startColumn, requirement.span.start.line, startColumn + length);
}

function isKnownEffectCall(name) {
  if (effectContractByName(normalizedEffectName(name))) {
    return true;
  }
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
  } else {
    start.offset = Math.max(startColumn - 1, 0);
    end.offset = Math.max(endColumn - 1, start.offset);
  }
  return {
    file: normalizedFile,
    start,
    end,
  };
}

function computeLineOffsets(source) {
  const starts = [0];
  const lines = [];
  let lineStartIndex = 0;
  let nextLineStartOffset = 0;
  const newlinePattern = /\r\n|\n|\r/g;
  for (const match of source.matchAll(newlinePattern)) {
    const line = source.slice(lineStartIndex, match.index);
    const segment = source.slice(lineStartIndex, match.index + match[0].length);
    lines.push(line);
    nextLineStartOffset += Buffer.byteLength(segment, "utf8");
    starts.push(nextLineStartOffset);
    lineStartIndex = match.index + match[0].length;
  }
  lines.push(source.slice(lineStartIndex));
  return { starts, lines };
}

function offsetFor(lineOffsetData, line, column) {
  const lineText = lineOffsetData.lines[line - 1] ?? "";
  const prefix = lineText.slice(0, Math.max(column - 1, 0));
  return (lineOffsetData.starts[line - 1] ?? 0) + Buffer.byteLength(prefix, "utf8");
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
    const access = {
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
    return withContractReferences(access, { ...access, args: context.args });
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
    const access = {
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
    return withContractReferences(access, { ...access, args: context.args });
  }
  return null;
}

function effectFamily(name) {
  const normalized = normalizedEffectName(name);
  const contract = effectContractByName(normalized);
  if (contract) return contract.family;
  if (/^(Git|git\.)/.test(normalized)) return "git";
  return normalized.split(/[.(]/)[0].toLowerCase();
}

function effectAction(name) {
  return effectContractByName(normalizedEffectName(name))?.action ?? null;
}

function effectContractId(effect) {
  return effectContractForAccess(effect)?.id ?? null;
}

function withContractReferences(access, contractSource = access) {
  return {
    ...access,
    contractId: effectContractId(access),
    contractArguments: effectContractArgumentRefs(contractSource),
  };
}

function normalizedEffectName(name) {
  return name.replace(/^Effect\./, "");
}

function effectContractByName(name) {
  return EFFECT_CONTRACTS.find((contract) => contractMatchesName(contract, name)) ?? null;
}

function effectContractById(id) {
  return EFFECT_CONTRACTS.find((contract) => contract.id === id) ?? null;
}

function contractMatchesName(contract, name) {
  return (contract.match.exact ?? []).includes(name)
    || (contract.match.prefix ?? []).some((prefix) => name.startsWith(prefix));
}

function effectContractForAccess(effect) {
  return EFFECT_CONTRACTS.find((contract) => {
    return effect.family === contract.family && effect.action === contract.action;
  }) ?? null;
}

function isResolvedEffectContract(effect) {
  return Boolean(effectContractForAccess(effect));
}

function effectContractForGrant(grant) {
  return effectContractArgumentForGrant(grant)?.contract ?? null;
}

function effectContractArgumentForGrant(grant) {
  for (const contract of EFFECT_CONTRACTS) {
    if (!isFamilyMatch(contract.family, grant.family) || contract.action !== grant.action) {
      continue;
    }
    const argument = contract.arguments.find((candidate) => {
      return candidate.key === grant.key || candidate.aliases.includes(grant.key);
    });
    if (argument) {
      return { contract, argument };
    }
  }
  return null;
}

function effectContractRegistry() {
  return {
    schema_version: EFFECT_CONTRACT_SCHEMA_VERSION,
    contracts: EFFECT_CONTRACTS.map((contract) => ({
      id: contract.id,
      family: contract.family,
      action: contract.action,
      risk: contract.risk,
      checkpoint: contract.checkpoint,
      match: {
        exact: contract.match.exact ?? [],
        prefix: contract.match.prefix ?? [],
      },
      arguments: contract.arguments.map((argument) => ({
        key: argument.key,
        aliases: argument.aliases,
        normalize: argument.normalize,
        trustSink: argument.trustSink ?? null,
      })),
    })),
  };
}

function isEffectAuthorized(effect, capabilities) {
  return capabilities.some((capability) => isFamilyMatch(effect.family, capability.family));
}

function approvalRequiredCapability(effect, capabilities) {
  return capabilities.find((capability) => {
    return isFamilyMatch(effect.family, capability.family)
      && !getCapabilityDenial(effect, [capability])
      && (capability.approvalRequired || matchingApprovalRequiredGrant(effect, capability));
  }) ?? null;
}

function capabilityApprovalPolicy(capability) {
  return capability.approvalRequired || (capability.grants ?? []).some((grant) => grant.approvalRequired)
    ? "required"
    : "none";
}

function matchingApprovalRequiredGrant(effect, capability) {
  return effectArguments(effect).some((argument) => {
    return (capability.grants ?? []).some((grant) => {
      return grant.approvalRequired
        && grant.action === effect.action
        && grantArgumentForEffectArgument(argument, grant)
        && isGrantMatch(argument, grant);
    });
  });
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
      .filter((grant) => grant.action === effect.action && grantArgumentForEffectArgument(argument, grant));

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
      allowed: candidateGrants.flatMap((grant) => grantArgumentValues(argument, grant)),
    };
  }

  return null;
}

function authorizationEdgeData(effect, capability) {
  const contractId = effectContractId(effect);
  const contractArguments = isPlainObject(effect.contractArguments)
    ? effect.contractArguments
    : effectContractArgumentRefs(effect);
  const grants = effectArguments(effect).map((argument) => {
    const grant = (capability.grants ?? []).find((candidate) => {
      return candidate.action === effect.action
        && grantArgumentForEffectArgument(argument, candidate)
        && isGrantMatch(argument, candidate);
    });
    if (!grant) return null;
    return authorizationGrantRecord(argument, grant, contractArguments[argument.key] ?? argument.key);
  }).filter(Boolean);
  return {
    contractId,
    contractArguments,
    grants,
  };
}

function getTrustFlowDiagnostic(effect) {
  const sink = trustSinkArgument(effect);
  if (!sink) {
    return null;
  }
  if (effectArgumentKind(effect, sink.key) === "string") {
    return null;
  }
  return {
    message: `effect '${effect.name}' uses nonliteral ${sink.description} '${sink.value}'.`,
    argument: sink.key,
    value: sink.value,
    trust: "untrusted",
  };
}

function trustSinkArgument(effect) {
  const sink = effectContractForAccess(effect)?.arguments.find((candidate) => {
    return candidate.trustSink && effectArgumentRawValue(effect, candidate.key) !== null;
  });
  if (!sink) {
    return null;
  }
  return {
    family: effect.family,
    action: effect.action,
    key: sink.key,
    description: sink.trustSink,
    value: effectArgumentRawValue(effect, sink.key),
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
  const sink = trustSinkArgument(effect);
  if (!sink) {
    return { zone: "unknown", source: "effect" };
  }
  const kind = effectArgumentKind(effect, sink.key);
  if (kind === "string") {
    return { zone: "trusted", source: "literal", argument: sink.key };
  }
  return { zone: "untrusted", source: kind ?? "unknown", argument: sink.key };
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
  const aliases = effectArgumentAliases(argument.argument ?? argument.key)
    .filter((alias) => alias !== argument.key);
  for (const key of aliases) {
    if (argSpans[key]) {
      return argSpans[key];
    }
  }
  return effect.span;
}

function effectArgumentKind(effect, key) {
  return effectArgumentAliasValues(effect.argKinds ?? {}, key).find(Boolean) ?? null;
}

function effectArgumentRawValue(effect, key) {
  return effectArgumentAliasValues(effect.args ?? {}, key).find((value) => typeof value === "string") ?? null;
}

function effectArgumentAliasValues(values, key) {
  return effectArgumentAliases(key).map((alias) => values[alias]);
}

function effectContractArgumentRefs(effect) {
  const contract = effectContractForAccess(effect);
  if (!contract) return {};
  const refs = {};
  const seenKeys = new Set();
  for (const argument of contract.arguments) {
    if (seenKeys.has(argument.key)) continue;
    const source = argument.aliases.find((alias) => typeof effect.args?.[alias] === "string");
    if (!source) continue;
    seenKeys.add(argument.key);
    refs[argument.key] = source;
  }
  return refs;
}

function validateContractArgumentRefs(contract, effectData) {
  if (!contract || !isPlainObject(effectData.contractArguments) || !isPlainObject(effectData.args)) {
    return false;
  }
  const contractArgumentsByKey = new Map();
  for (const argument of contract.arguments) {
    const existing = contractArgumentsByKey.get(argument.key) ?? new Set();
    for (const alias of argument.aliases) {
      existing.add(alias);
    }
    contractArgumentsByKey.set(argument.key, existing);
  }
  return Object.entries(effectData.contractArguments).every(([key, source]) => {
    return typeof source === "string"
      && source.trim() !== ""
      && contractArgumentsByKey.get(key)?.has(source)
      && typeof effectData.args[source] === "string";
  });
}

function effectArgumentAliases(key) {
  const aliases = EFFECT_CONTRACTS.flatMap((contract) => contract.arguments)
    .filter((argument) => argument.key === key)
    .flatMap((argument) => argument.aliases);
  return aliases.length > 0 ? [...new Set([key, ...aliases])] : [key];
}

function effectArguments(effect) {
  const contract = effectContractForAccess(effect);
  if (!contract) return [];
  const seenKeys = new Set();
  return contract.arguments.map((argument) => {
    if (seenKeys.has(argument.key)) return null;
    const rawValue = argument.aliases
      .map((alias) => effect.args[alias])
      .find((value) => typeof value === "string");
    if (!rawValue) return null;
    seenKeys.add(argument.key);
    return { key: argument.key, value: normalizeEffectArgument(rawValue, argument.normalize) };
  }).filter(Boolean);
}

function normalizeEffectArgument(value, kind) {
  if (kind === "command") return normalizeCommand(value);
  if (kind === "domain") return normalizeDomain(value);
  if (kind === "url_domain") return domainFromUrl(value) ?? value;
  if (kind === "ref") return normalizeRefName(value);
  if (kind === "commit_message") return normalizeCommitMessage(value);
  if (kind === "deploy_target") return normalizeDeployTarget(value);
  if (kind === "secret") return normalizeSecretName(value);
  if (kind === "ticket") return normalizeTicketRef(value);
  return value;
}

function isGrantMatch(argument, grant) {
  const grantValues = grantArgumentValues(argument, grant);
  if (grantValues.length === 0) {
    return false;
  }
  if (argument.key === "path") {
    return grantValues.some((value) => isPathGrantMatch(argument.value, value));
  }
  if (argument.key === "domain") {
    return grantValues.some((value) => isDomainGrantMatch(argument.value, value));
  }
  if (argument.key === "branch" || argument.key === "remote") {
    return grantValues.some((value) => normalizeRefName(argument.value) === normalizeRefName(value));
  }
  if (argument.key === "message") {
    return grantValues.some((value) => normalizeCommitMessage(argument.value) === normalizeCommitMessage(value));
  }
  if (argument.key === "target") {
    return grantValues.some((value) => normalizeDeployTarget(argument.value) === normalizeDeployTarget(value));
  }
  if (argument.key === "name") {
    return grantValues.some((value) => normalizeSecretName(argument.value) === normalizeSecretName(value));
  }
  if (argument.key === "id") {
    return grantValues.some((value) => normalizeTicketRef(argument.value) === normalizeTicketRef(value));
  }
  return grantValues.some((value) => normalizeCommand(argument.value) === normalizeCommand(value));
}

function grantArgumentForEffectArgument(argument, grant) {
  const args = Array.isArray(grant.args) && grant.args.length > 0
    ? grant.args
    : [{ key: grant.key, value: grant.value }];
  return args.find((candidate) => candidate.key === argument.key) ?? null;
}

function grantArgumentValues(argument, grant) {
  const grantArgument = grantArgumentForEffectArgument(argument, grant);
  if (!grantArgument) {
    return [];
  }
  if (Array.isArray(grantArgument.value)) {
    return grantArgument.value;
  }
  return typeof grantArgument.value === "string" ? [grantArgument.value] : [];
}

function isPathGrantMatch(value, pattern) {
  const normalizedValue = normalizePathLike(value);
  const normalizedPattern = normalizePathLike(pattern);
  if (!isPackageRelativePath(normalizedValue) || !isPackageRelativePath(normalizedPattern)) {
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

function isPackageRelativePath(value) {
  return !value.startsWith("../") && !value.startsWith("/");
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
