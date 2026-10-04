import { readFileSync, existsSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { ModelRuntime } from "@earendil-works/pi-coding-agent";
import { assistantCodexAuth } from "../../src/codex-auth.ts";
import { hash, readJSON } from "./suite.mjs";
import { saveJSON } from "./artifacts.mjs";

// Measure the provider's incremental input accounting instead of assuming that
// a public tokenizer's encoding matches the deployed model's private tokenizer.
const [specPath, output] = process.argv.slice(2);
if (!specPath || !output) throw new Error("Use instruction-tokens.mjs spec.json ignored-output.json");
if (existsSync(output)) throw new Error("Instruction measurement output already exists; preserve it and choose a fresh path");
const spec = readJSON(specPath);
const prompts = [{ id: "control", text: "You are a helpful assistant." }, ...spec.prompts.map(item => ({
  id: item.id, text: item.files.map(file => readFileSync(resolve(dirname(specPath), file), "utf8")).join("\n\n"),
}))];
if (new Set(prompts.map(p => p.id)).size !== prompts.length) throw new Error("Instruction IDs must be unique");
const runtime = await ModelRuntime.create({ authPath: assistantCodexAuth(dirname(output)), modelsPath: null, refreshOnCreate: false });
const model = runtime.getModel("openai-codex", "gpt-6-luna");
if (!model) throw new Error("Instruction probe model unavailable");
const artifact = { model: model.id, method: "Provider-reported first-request input, including cached input, relative to the explicit control 'You are a helpful assistant.'. Constant user message, effort none, two order-rotated repeats. Baseline-minus-candidate input is the measured instruction reduction; relative counts are not standalone tokenizer counts.",
  specHash: hash(spec), prompts: prompts.map(p => ({ id: p.id, hash: hash(p.text) })), results: [] };
for (let repeat = 1; repeat <= 2; repeat++) {
  const order = repeat === 1 ? prompts : prompts.toReversed();
  let cursor = 0;
  await Promise.all(Array.from({ length: 2 }, async () => {
    while (cursor < order.length) {
      const prompt = order[cursor++]; let response;
      const answer = await runtime.completeSimple(model, { systemPrompt: prompt.text, messages: [{ role: "user", timestamp: 0, content: "Return OK." }] }, {
        reasoning: "off", transport: "sse", maxRetries: 0, signal: AbortSignal.timeout(60000),
        onPayload: payload => {
          if (payload.instructions !== prompt.text) throw new Error("Effective provider instructions differ from the probe");
          return { ...payload, service_tier: "priority" };
        },
        onProviderStreamEvent: event => { if (event.type === "response.completed") response = { model: event.response?.model, tier: event.response?.service_tier }; },
      });
      if (answer.stopReason !== "stop") throw new Error(answer.errorMessage || answer.stopReason);
      const usage = answer.usage;
      artifact.results.push({ id: prompt.id, repeat, response, usage, inputIncludingCache: usage.input + usage.cacheRead + usage.cacheWrite });
      saveJSON(output, artifact);
    }
  }));
}
const controls = artifact.results.filter(r => r.id === "control");
if (controls[0].inputIncludingCache !== controls[1].inputIncludingCache) throw new Error("Instruction control changed; cannot attribute input difference");
artifact.measurements = prompts.slice(1).map(prompt => {
  const runs = artifact.results.filter(r => r.id === prompt.id);
  if (runs[0].inputIncludingCache !== runs[1].inputIncludingCache) throw new Error("Instruction input accounting changed across repeats");
  return { id: prompt.id, hash: hash(prompt.text), incrementalInputTokens: runs[0].inputIncludingCache - controls[0].inputIncludingCache };
});
artifact.complete = true;
saveJSON(output, artifact);
console.log(JSON.stringify(artifact.measurements, null, 2));
