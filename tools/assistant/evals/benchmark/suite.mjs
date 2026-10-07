import { readFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { createHash } from "node:crypto";

export const hash = value => createHash("sha256").update(typeof value === "string" ? value : JSON.stringify(value)).digest("hex");
export const readJSON = path => JSON.parse(readFileSync(path, "utf8"));
export function loadSuite(path, split) {
  const root = dirname(resolve(path));
  const config = readJSON(path);
  if (!config.id || !["suggestion", "agent"].includes(config.mode)) throw new Error("Suite needs an id and suggestion or agent mode");
  if (config.execution === "role-integration" && (config.mode !== "agent" || !["coordinator", "session", "reviewer"].includes(config.role))) throw new Error("Native role integration needs an agent suite and coordinator, session, or reviewer role");
  if (!["development", "challenge", "confirmation"].includes(split)) throw new Error("Unknown dataset split");
  const cases = (config.datasets[split] || []).flatMap(file => readJSON(resolve(root, file)));
  const seen = new Set();
  for (const test of cases) {
    if (!test.id || !test.family || !test.category || !test.rubric || !Array.isArray(test.messages) || seen.has(test.id)) throw new Error("Cases require unique id, family, category, rubric and messages");
    seen.add(test.id);
  }
  if (!cases.length) throw new Error(split === "confirmation" ? "No fresh confirmation set configured. Add new families before freezing; exposed cases are regression data." : "Dataset is empty");
  const variants = config.variants.map(variant => {
    const resources = Object.fromEntries(Object.entries(variant.resources || {}).map(([key, file]) => [key, readFileSync(resolve(root, file), "utf8")]));
    const sections = variant.files.map(file => readFileSync(resolve(root, file), "utf8"));
    const prompt = sections.join("\n\n");
    if (!variant.id || !prompt.trim()) throw new Error("Variants need an id and nonempty instructions");
    return { ...variant, sections, prompt, resources, hash: hash({ prompt, resources }), words: prompt.trim().split(/\s+/).length, effort: variant.effort || config.effort };
  });
  if (new Set(variants.map(v => v.id)).size !== variants.length) throw new Error("Variant ids must be unique");
  if (variants.some(v => !["off", "low", "high"].includes(v.effort))) throw new Error("Effort must be off, low or high");
  const allFamilies = {};
  const allIds = {};
  const confirmationInputs = new Set();
  const developmentInputs = new Set();
  for (const [name, files] of Object.entries(config.datasets)) {
    const data = files.flatMap(file => readJSON(resolve(root, file)));
    for (const test of data) {
      const signature = hash({ messages: test.messages, tools: test.tools || [], fixtures: test.fixtures || [], initialState: test.initialState || {}, files: test.files || {}, allowedCommands: test.allowedCommands || [], homeState: test.homeState || {} });
      if (name === "confirmation") confirmationInputs.add(signature);
      else developmentInputs.add(signature);
    }
    allFamilies[name] = new Set(data.map(test => test.family));
    allIds[name] = new Set(data.map(test => test.id));
  }
  for (const family of allFamilies.confirmation || []) {
    if (allFamilies.development?.has(family) || allFamilies.challenge?.has(family)) throw new Error(`Confirmation family reused: ${family}`);
  }
  for (const id of allIds.confirmation || []) {
    if (allIds.development?.has(id) || allIds.challenge?.has(id)) throw new Error(`Confirmation id reused: ${id}`);
  }
  if ([...confirmationInputs].some(signature => developmentInputs.has(signature))) throw new Error("Confirmation input reused under a different id or family");
  const harness = Object.fromEntries(["suite.mjs", "trial.mjs", "grading.mjs", "statistics.mjs", "judge.md", "judge.mjs", "artifacts.mjs", "cli.mjs", "adjudicate.mjs", "retry.mjs"].map(file => [file, hash(readFileSync(new URL(file, import.meta.url), "utf8"))]));
  if (["researcher-integration", "role-integration"].includes(config.execution)) for (const file of ["role-integration.mjs", "integration-workspace.mjs", "../../src/pi.ts", "../../src/state.ts", "../../src/agent-resources.ts", "../../src/hosted-search.ts", "../../src/home-routing.ts", "../../src/computer-use.ts", "../../package.json", "../../package-lock.json", "../../../../AGENTS.md"])
    harness[file] = hash(readFileSync(new URL(file, import.meta.url), "utf8"));
  return { path: resolve(path), config, split, cases, variants, harness, fingerprint: hash({ config, split, cases, variants, harness }) };
}

export function schedule(cases, variants, repeats) {
  if (!Number.isInteger(repeats) || repeats < 1) throw new Error("Repeats must be a positive integer");
  const jobs = [];
  for (let repeat = 1; repeat <= repeats; repeat++) {
    for (const [index, test] of cases.entries()) {
      const offset = (index + repeat - 1) % variants.length;
      const order = [...variants.slice(offset), ...variants.slice(0, offset)];
      if (repeat % 2 === 0) order.reverse();
      for (const variant of order) jobs.push({ id: hash([test.id, variant.id, repeat]).slice(0, 20), test, variant, repeat });
    }
  }
  return jobs;
}
