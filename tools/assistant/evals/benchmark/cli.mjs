import { existsSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { ModelRuntime } from "@earendil-works/pi-coding-agent";
import { assistantCodexAuth } from "../../src/codex-auth.ts";
import { loadSuite, schedule, hash, readJSON } from "./suite.mjs";
import { runTrial } from "./trial.mjs";
import { runResearcherIntegration } from "./researcher-integration.mjs";
import { blindCards } from "./grading.mjs";
import { saveJSON, makeReport } from "./artifacts.mjs";

const [command, path, ...args] = process.argv.slice(2);
const allowed = new Set(["split", "repeats", "concurrency", "variants", "out", "freeze", "resume", "reviews"]);
const options = {};
for (let i = 0; i < args.length; i++) {
  const name = args[i].replace(/^--/, "");
  if (!args[i].startsWith("--") || !allowed.has(name) || options[name] !== undefined) throw new Error(`Invalid option ${args[i]}`);
  if (name === "resume") options[name] = true;
  else { if (!args[i + 1] || args[i + 1].startsWith("--")) throw new Error(`Missing value for ${name}`); options[name] = args[++i]; }
}
if (!path || !["plan", "freeze", "run", "review", "report"].includes(command)) throw new Error("Use plan|freeze|run suite.json, review|report run.json; see evals/benchmark/README.md");
if (command === "review" || command === "report") {
  const run = readJSON(path);
  if (command === "review") saveJSON(options.out || `${path}.blind.json`, { inputHash: hash(run), cards: blindCards(run) });
  else {
    if (!options.reviews) throw new Error("report requires --reviews");
    saveJSON(options.out || `${path}.report.json`, makeReport(run, readJSON(options.reviews)));
  }
} else {
  const suite = loadSuite(path, options.split || "development");
  if (options.variants) {
    const ids = options.variants.split(",");
    if (new Set(ids).size !== ids.length) throw new Error("Variant selection must not repeat IDs");
    if (ids.some(id => !suite.variants.some(v => v.id === id))) throw new Error("Unknown requested variant");
    suite.variants = suite.variants.filter(v => ids.includes(v.id));
  }
  const repeats = Number(options.repeats || 3);
  const concurrency = Number(options.concurrency || 2);
  if (!Number.isInteger(concurrency) || concurrency < 1 || concurrency > 4) throw new Error("Concurrency must be 1–4");
  const jobs = schedule(suite.cases, suite.variants, repeats);
  const fingerprint = hash({ suite: suite.fingerprint, variants: suite.variants.map(v => v.id), repeats, concurrency });
  const manifest = { fingerprint, suiteFingerprint: suite.fingerprint, split: suite.split, variants: suite.variants.map(v => ({ id: v.id, hash: v.hash, effort: v.effort })), repeats, concurrency, jobs: jobs.length };
  if (command === "plan") console.log(JSON.stringify(manifest, null, 2));
  else if (command === "freeze") saveJSON(options.out || `${path}.freeze.json`, manifest);
  else {
    if (suite.split === "confirmation" && !options.freeze) throw new Error("Confirmation requires a frozen manifest from before outputs were inspected");
    if (options.freeze && readJSON(options.freeze).fingerprint !== fingerprint) throw new Error("Frozen manifest differs from instructions, cases or run settings");
    const out = options.out ? resolve(options.out) : new URL(`../../../../.precedent/assistant-benchmarks/${suite.config.id}-${new Date().toISOString().replaceAll(":", "-")}.json`, import.meta.url).pathname;
    if (options.resume && !existsSync(out)) throw new Error("No existing run to resume");
    if (existsSync(out) && !options.resume) throw new Error("Output already exists; choose a new path or --resume");
    const run = options.resume && existsSync(out) ? readJSON(out) : { ...manifest, suite: suite.config.id, mode: suite.config.mode, startedAt: new Date().toISOString(),
      provenance: suite.config.provenance, execution: suite.config.execution || "fixture", selection: suite.config.selection, harness: suite.harness, model: suite.config.model || "gpt-6-luna", cases: suite.cases, variants: suite.variants, results: [] };
    if (run.fingerprint !== fingerprint) throw new Error("Resume inputs changed");
    saveJSON(out, run);
    const runtime = await ModelRuntime.create({ authPath: assistantCodexAuth(dirname(out)), modelsPath: null, refreshOnCreate: false });
    const model = runtime.getModel("openai-codex", run.model);
    if (!model) throw new Error("Configured model unavailable");
    const complete = new Set(run.results.map(r => r.id));
    const pending = jobs.filter(job => !complete.has(job.id));
    let cursor = 0; let errors = 0; let stopped = false;
    await Promise.all(Array.from({ length: concurrency }, async () => {
      while (!stopped && cursor < pending.length) {
        const job = pending[cursor++];
        const record = await (suite.config.execution === "researcher-integration" ? runResearcherIntegration : runTrial)(runtime, model, suite, job);
        run.results.push(record); saveJSON(out, run);
        errors = record.error ? errors + 1 : 0;
        console.log(`${run.results.length}/${jobs.length} ${job.test.id} ${job.variant.id} #${job.repeat}: ${record.error || record.text || "fixture outcome"}`);
        if (errors >= 3) stopped = true;
      }
    }));
    run.finishedAt = new Date().toISOString(); run.complete = run.results.length === jobs.length; saveJSON(out, run);
    if (!run.complete) throw new Error(`Stopped after repeated errors; partial results saved to ${out}`);
    console.log(`Saved ${run.results.length} trials to ${out}`);
  }
}
