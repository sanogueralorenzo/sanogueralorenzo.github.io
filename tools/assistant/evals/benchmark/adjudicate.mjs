import { readJSON, hash } from './suite.mjs';
import { validateReviews, blindCards } from './grading.mjs';
import { saveJSON } from './artifacts.mjs';

const [runPath, reviewPath, decisionsPath, output] = process.argv.slice(2);
if (!output) throw new Error('Use adjudicate.mjs run.json reviews.json decisions.json output.json');
const run = readJSON(runPath), source = readJSON(reviewPath), decisions = readJSON(decisionsPath);
if (source.inputHash !== hash(run) || !decisions.provenance || !Array.isArray(decisions.overrides)) throw new Error('Adjudication requires matching run and named review provenance');
const result = structuredClone(source);
const seen = new Set();
result.adjudications = [...(result.adjudications || [])];
for (const override of decisions.overrides) {
  const index = result.reviews.findIndex(r => r.id === override.id);
  if (index < 0 || seen.has(override.id) || !override.reason) throw new Error('Unknown, duplicate, or unexplained adjudication');
  seen.add(override.id);
  result.adjudications.push({ original: result.reviews[index], reason: override.reason, provenance: decisions.provenance });
  result.reviews[index] = { ...result.reviews[index], ...override.review, id: override.id };
}
validateReviews(blindCards(run), result.reviews);
result.checkWaivers = [...(source.checkWaivers || []), ...(decisions.checkWaivers || []).map(w => ({ ...w, provenance: decisions.provenance }))];
result.adjudicationSourceHash = hash(source);
saveJSON(output, result);
