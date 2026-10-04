import { readFileSync, existsSync } from "node:fs";
import { dirname } from "node:path";
import { ModelRuntime } from "@earendil-works/pi-coding-agent";
import { assistantCodexAuth } from "../../src/codex-auth.ts";
import { readJSON, hash } from "./suite.mjs";
import { blindCards, validateReviews } from "./grading.mjs";
import { saveJSON } from "./artifacts.mjs";

const [input, output, effort = "high", resume] = process.argv.slice(2);
if (!input || !output || !["off", "low", "high"].includes(effort) || resume && resume !== "--resume") throw new Error("Use judge.mjs run-or-calibration.json reviews.json off|low|high [--resume]");
if (resume && !existsSync(output)) throw new Error("No existing review artifact to resume");
if (existsSync(output) && !resume) throw new Error("Review output already exists; choose a new path or explicitly --resume");
const data = readJSON(input);
const cards = data.cards || blindCards(data);
const policy = readFileSync(new URL("./judge.md", import.meta.url), "utf8");
const runtime = await ModelRuntime.create({ authPath: assistantCodexAuth(dirname(output)), modelsPath: null, refreshOnCreate: false });
const model = runtime.getModel("openai-codex", "gpt-6-luna");
if (!model) throw new Error("Judge model unavailable");
const artifact = existsSync(output) ? readJSON(output) : { provenance: "Blinded model-assisted review; not independent human validation", inputHash: data.inputHash || hash(data), sourceHash: hash(data), policyHash: hash(policy), model: model.id, effort, reviews: [], usage: [], errors: [] };
if (artifact.sourceHash !== hash(data) || artifact.policyHash !== hash(policy) || artifact.effort !== effort) throw new Error("Review resume inputs or policy changed");
artifact.repairHistory = [...(artifact.repairHistory || []), ...artifact.errors];
artifact.errors = [];
const reviewed = new Set(artifact.reviews.map(r => r.id));
const groups = [];
for (const card of cards) {
  if (reviewed.has(card.id)) continue;
  const key = hash([card.mode, card.caseId, card.messages, card.rubric]);
  let group = groups.find(item => item.key === key && item.items.length < 10);
  if (!group) { group = { key, mode: card.mode, messages: card.messages, rubric: card.rubric, acceptable: card.acceptable, forbidden: card.forbidden, items: [] }; groups.push(group); }
  group.items.push({ id: card.id, text: card.text, trace: card.trace, state: card.state, checks: card.checks });
}
let cursor = 0;
await Promise.all(Array.from({ length: 2 }, async () => {
  while (cursor < groups.length) {
    const group = groups[cursor++];
    let raw;
    try {
      const answer = await runtime.completeSimple(model, { systemPrompt: policy, messages: [{ role: "user", timestamp: 0, content: JSON.stringify(group) }] }, {
        reasoning: effort, transport: "sse", maxRetries: 0, signal: AbortSignal.timeout(60000),
        onPayload: payload => {
          if (payload.reasoning?.effort !== (effort === "off" ? "none" : effort)) throw new Error("Judge reasoning mismatch");
          return { ...payload, service_tier: "priority" };
        },
      });
      if (answer.stopReason !== "stop") throw new Error(answer.errorMessage || answer.stopReason);
      raw = answer.content.filter(p => p.type === "text").map(p => p.text).join("");
      const reviews = JSON.parse(raw).reviews;
      validateReviews(group.items, reviews);
      artifact.reviews.push(...reviews); artifact.usage.push(answer.usage);
    } catch (error) { artifact.errors.push({ ids: group.items.map(i => i.id), error: error.message, raw }); }
    saveJSON(output, artifact);
    console.log(`${artifact.reviews.length}/${cards.length} reviewed; ${artifact.errors.length} batches need repair`);
  }
}));
if (artifact.errors.length) throw new Error("Judge errors saved; repair or adjudicate before reporting");
validateReviews(cards, artifact.reviews);
if (data.expected) {
  artifact.calibration = data.expected.map(gold => {
    const actual = artifact.reviews.find(r => r.id === gold.id);
    return { id: gold.id, utility: gold.utility.includes(actual.utility), constraints: gold.constraints.includes(actual.constraints), actual, expected: gold };
  });
  artifact.calibrationAccuracy = artifact.calibration.filter(r => r.utility && r.constraints).length / artifact.calibration.length;
  saveJSON(output, artifact);
  console.log(`Calibration agreement: ${(100 * artifact.calibrationAccuracy).toFixed(1)}%`);
}
