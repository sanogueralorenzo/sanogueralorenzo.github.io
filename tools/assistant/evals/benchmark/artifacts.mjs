import { writeFileSync, renameSync, mkdirSync } from "node:fs";
import { dirname } from "node:path";
import { blindCards, checks, validateReviews } from "./grading.mjs";
import { hash } from "./suite.mjs";
import { mean, percentile, pairedInterval } from "./statistics.mjs";

export function saveJSON(path, value) {
  mkdirSync(dirname(path), { recursive: true });
  writeFileSync(`${path}.tmp`, JSON.stringify(value, null, 2) + "\n", { mode: 0o600 });
  renameSync(`${path}.tmp`, path);
}
export function makeReport(run, reviewArtifact) {
  if (!run.complete || reviewArtifact.inputHash !== hash(run) || !reviewArtifact.provenance || reviewArtifact.errors?.length) throw new Error("Reporting requires a complete run and matching, complete review artifact");
  const reviews = reviewArtifact.reviews;
  const waivers = reviewArtifact.checkWaivers || [];
  const waiverKeys = new Set();
  for (const waiver of waivers) {
    const test = run.cases.find(c => c.id === waiver.caseId);
    const key = `${waiver.caseId}:${waiver.index}`;
    if (!test || !Number.isInteger(waiver.index) || !test.checks?.[waiver.index] || !waiver.reason || !waiver.provenance || waiverKeys.has(key)) throw new Error("Check waivers require a known case/check and explicit unique rationale");
    waiverKeys.add(key);
  }
  const resolvedChecks = record => {
    const test = run.cases.find(c => c.id === record.caseId);
    return checks(record, { ...test, checks: (test.checks || []).filter((_, index) => !waiverKeys.has(`${test.id}:${index}`)) }, run.mode);
  };
  const cards = blindCards(run);
  validateReviews(cards, reviews);
  const byId = new Map(reviews.map(r => [r.id, r]));
  const rows = run.results.filter(r => !r.error).map(record => {
    const review = byId.get(hash([run.fingerprint, record.id, "blind"]).slice(0, 24));
    return { ...record, review, score: { useful: 2, acceptable: 1, missed: 0, wrong: 0, uncertain: 0 }[review.utility] };
  });
  const metrics = {};
  for (const variant of run.variants) {
    const all = run.results.filter(r => r.variant === variant.id);
    const selected = rows.filter(r => r.variant === variant.id);
    metrics[variant.id] = { attempts: all.length, retriedInfrastructureErrors: (run.infrastructureRetries || []).flatMap(r => r.failures).filter(r => r.variant === variant.id).length, infrastructureErrors: all.filter(r => r.error).length,
      utilityTrials: selected.filter(r => r.review.utility !== "uncertain").length, useful: selected.filter(r => r.review.utility === "useful").length, acceptable: selected.filter(r => r.review.utility === "acceptable").length,
      missed: selected.filter(r => r.review.utility === "missed").length, wrong: selected.filter(r => r.review.utility === "wrong").length,
      constraintViolations: selected.filter(r => r.review.constraints === "violated").length,
      uncertain: selected.filter(r => r.review.utility === "uncertain" || r.review.constraints === "uncertain" || r.review.confidence === "low").length,
      deterministicFailures: selected.filter(r => resolvedChecks(r).some(c => !c.ok)).length,
      deadlineFallbacks: all.filter(r => r.deadlineExceeded).length, meanUtility: mean(selected.filter(r => r.review.utility !== "uncertain").map(r => r.score)),
      inputTokens: mean(selected.map(r => r.usage.input)), outputTokens: mean(selected.map(r => r.usage.output)), totalTokens: mean(selected.map(r => r.usage.totalTokens)),
      cacheReadTokens: selected.reduce((sum, r) => sum + r.usage.cacheRead, 0), medianMs: percentile(all.map(r => r.elapsedMs), .5), p90Ms: percentile(all.map(r => r.elapsedMs), .9),
      categories: Object.fromEntries([...new Set(selected.map(r => r.category))].map(category => {
        const subset = selected.filter(r => r.category === category);
        return [category, { attempts: subset.length, meanUtility: mean(subset.filter(r => r.review.utility !== "uncertain").map(r => r.score)), violations: subset.filter(r => r.review.constraints === "violated").length }];
      })) };
  }
  const baseline = run.variants[0].id;
  const providerResponses = rows.flatMap(r => r.requests || []).map(r => r.response).filter(Boolean);
  const providerTiers = Object.fromEntries([...new Set(providerResponses.map(r => r.tier || "unknown"))].map(tier => [tier, providerResponses.filter(r => (r.tier || "unknown") === tier).length]));
  const comparisons = Object.fromEntries(run.variants.slice(1).map(v => [v.id, pairedInterval(rows.filter(r => r.review.utility !== "uncertain"), baseline, v.id)]));
  const selection = {};
  for (const [id, interval] of Object.entries(comparisons)) {
    const base = metrics[baseline], value = metrics[id];
    const saving = 100 * (1 - value.totalTokens / base.totalTokens);
    const policy = run.selection;
    const reasons = [];
    if (!policy) reasons.push("No predeclared selection policy");
    else {
      if (!interval.pairedFamilies || interval.low < -policy.maxMeanUtilityLoss) reasons.push("Utility interval does not exclude material harm");
      if (saving < policy.minTotalTokenSavingPercent) reasons.push("Insufficient total-token saving");
      if (policy.requireZeroNewConstraintViolations && value.constraintViolations) reasons.push("Constraint violations require rejection or explicit case audit");
    }
    if (base.infrastructureErrors || value.infrastructureErrors || base.uncertain || value.uncertain) reasons.push("Unresolved infrastructure or grading uncertainty");
    if (value.deterministicFailures) reasons.push("Required outcome checks failed");
    if (run.split !== "confirmation") reasons.push("Development or challenge evidence cannot promote a candidate");
    selection[id] = { totalTokenSavingPercent: saving, status: reasons.length ? "not-established" : "meets-local-gate", reasons };
  }
  return { checkWaivers: waivers.map(w => ({ ...w, originalCheck: run.cases.find(c => c.id === w.caseId).checks[w.index] })), providerTiers, reviewProvenance: reviewArtifact.provenance, policyHash: reviewArtifact.policyHash, adjudications: reviewArtifact.adjudications?.length || 0, selection, suite: run.suite, split: run.split, fingerprint: run.fingerprint, baseline, metrics, comparisons,
    limitations: ["Rubric review provenance is supplied in the review artifact; model-assisted reviews are not human validation.", "Repeated trials share case families and must not be counted as independent tasks.", "Fixture tool execution is bounded replay, not a production integration test.", "A zero observed violation count does not prove zero risk; inspect disagreements and critical outputs."] };
}
