import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { ModelRuntime } from "@earendil-works/pi-coding-agent";
import { assistantCodexAuth } from "../../src/codex-auth.ts";

const directory = fileURLToPath(new URL(".", import.meta.url));
const cases = JSON.parse(readFileSync(new URL(process.argv[2] || "cases.json", import.meta.url), "utf8"));
const systemPrompt = readFileSync(new URL("prompt.txt", import.meta.url), "utf8");
const outputDirectory = resolve(directory, "../../../../.precedent/assistant-suggestions");
mkdirSync(outputDirectory, { recursive: true });
const runtime = await ModelRuntime.create({ authPath: assistantCodexAuth(outputDirectory), modelsPath: null, refreshOnCreate: false });
const model = runtime.getModel("openai-codex", "gpt-6-luna");
if (!model) throw new Error("gpt-6-luna is unavailable");

const results = [];
const startedAt = new Date().toISOString();
const repeats = Number(process.argv[3] || 2);
if (!Number.isInteger(repeats) || repeats < 1) throw new Error("Repeat count must be a positive integer");
const levels = (process.argv[4] || "low,high").split(",");
if (new Set(levels).size !== levels.length || levels.some((level) => !["off", "low", "high"].includes(level)))
  throw new Error("Efforts must be a comma-separated list of off, low, or high without duplicates");
const output = resolve(outputDirectory, `results-${startedAt.replaceAll(":", "-")}.json`);
const save = () => writeFileSync(output, JSON.stringify({ startedAt, model: model.id, requestedTier: "priority", transport: "sse", repeats, levels,
  context: "Isolated compact conversation context; no tools or live session transcript. Cache usage is recorded rather than assumed.",
  systemPrompt, cases, results }, null, 2));
let consecutiveErrors = 0;
save();

for (let repeat = 1; repeat <= repeats; repeat++) {
  for (const [index, test] of cases.entries()) {
    const efforts = (index + repeat) % 2 ? levels : [...levels].reverse();
    for (const effort of efforts) {
      const started = performance.now();
      let firstTextMs = null;
      let providerRequest;
      let providerResponse;
      const record = { caseId: test.id, expected: test.expected, repeat, effort };
      try {
        const stream = runtime.streamSimple(model, { systemPrompt, messages: [{ role: "user", timestamp: 0,
          content: JSON.stringify({ conversation: test.messages }) }] }, {
          reasoning: effort, sessionId: `suggestion-eval-${test.id}`, transport: "sse", maxRetries: 0,
          signal: AbortSignal.timeout(60_000),
          onPayload: (payload) => {
            const request = { ...payload, service_tier: "priority" };
            providerRequest = { model: request.model, effort: request.reasoning?.effort, tier: request.service_tier };
            if (providerRequest.effort !== (effort === "off" ? "none" : effort))
              throw new Error(`Requested ${effort}, but provider payload uses ${providerRequest.effort}`);
            return request;
          },
          onProviderStreamEvent: (event) => {
            if (event.type === "response.completed") providerResponse = {
              model: event.response?.model, tier: event.response?.service_tier,
              reasoningTokens: event.response?.usage?.output_tokens_details?.reasoning_tokens,
            };
          },
        });
        for await (const event of stream) {
          if (event.type === "text_delta" && event.delta && firstTextMs === null) firstTextMs = performance.now() - started;
        }
        const answer = await stream.result();
        const text = answer.content.filter((part) => part.type === "text").map((part) => part.text).join("\n").trim();
        Object.assign(record, { elapsedMs: performance.now() - started, firstTextMs, text, abstained: text === "NONE",
          words: text ? text.split(/\s+/).length : 0, stopReason: answer.stopReason, usage: answer.usage,
          providerRequest, providerResponse });
        if (answer.stopReason === "error" || answer.stopReason === "aborted") throw new Error(answer.errorMessage || answer.stopReason);
        if (!text) throw new Error("Empty response");
        consecutiveErrors = 0;
      } catch (error) {
        Object.assign(record, { elapsedMs: performance.now() - started, firstTextMs, error: error.message, providerRequest, providerResponse });
        consecutiveErrors++;
      }
      results.push(record);
      save();
      console.log(`${results.length}/${cases.length * repeats * levels.length} ${test.id} ${effort} #${repeat}: ${(record.elapsedMs / 1000).toFixed(2)}s — ${record.error || record.text}`);
      if (consecutiveErrors >= 3) throw new Error(`Three consecutive requests failed; partial results are saved to ${output}`);
    }
  }
}
console.table(levels.map((effort) => {
  const rows = results.filter((row) => row.effort === effort && !row.error);
  const times = rows.map((row) => row.elapsedMs / 1000).sort((a, b) => a - b);
  const middle = Math.floor(times.length / 2);
  const suggestions = rows.filter((row) => row.expected === "suggest");
  const abstentions = rows.filter((row) => row.expected === "none");
  return { effort, completed: rows.length, errors: results.filter((row) => row.effort === effort && row.error).length,
    medianSeconds: times.length ? Number(((times[middle] + times[(times.length - 1) >> 1]) / 2).toFixed(2)) : null,
    p90Seconds: times.length ? Number(times[Math.ceil(times.length * .9) - 1].toFixed(2)) : null,
    within3Seconds: times.filter((time) => time <= 3).length,
    suggestions: `${suggestions.filter((row) => !row.abstained).length}/${suggestions.length}`,
    correctAbstentions: `${abstentions.filter((row) => row.abstained).length}/${abstentions.length}`,
    outputTokens: rows.reduce((sum, row) => sum + row.usage.output, 0),
  };
}));
console.log(`Saved ${results.length} measured requests to ${output}`);
