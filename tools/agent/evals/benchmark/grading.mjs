import { isDeepStrictEqual } from "node:util";
import { matches } from "./trial.mjs";
import { hash } from "./suite.mjs";

export function checks(record, test, mode) {
  const results = [];
  if (record.error) return [{ kind: "infrastructure", ok: false, detail: record.error }];
  if (record.agentFailure) results.push({ kind: "outcome", ok: false, detail: record.agentFailure });
  if (mode === "suggestion") results.push({ kind: "format", ok: record.text === "NONE" || Boolean(record.text) && !/[\r\n\x00-\x1f]/.test(record.text) && record.text.length <= 180 && record.text.split(/\s+/).length <= 16 });
  const calls = record.trace.filter(item => item.role === "tool");
  for (const check of test.checks || []) {
    let ok;
    if (check.type === "state") ok = matches(record.state, check.value);
    else if (check.type === "tool") ok = calls.filter(call => call.name === check.name && matches(call.arguments, check.arguments || {})).length >= (check.min || 1);
    else if (check.type === "noTool") ok = !calls.some(call => check.names.includes(call.name) && matches(call.arguments, check.arguments || {}));
    else if (check.type === "absent") ok = check.keys.every(key => record.state[key] === undefined);
    else if (check.type === "toolOrder") {
      const indices = side => calls.flatMap((call, index) => call.name === side.name && matches(call.arguments, side.arguments || {}) ? [index] : []);
      const before = indices(check.before), after = indices(check.after);
      ok = before.length > 0 && after.length > 0 && (check.position === "last" ? before.at(-1) < after.at(-1) : before[0] < after[0]);
    }
    else if (check.type === "json") { try { const actual = JSON.parse(check.stateKey ? record.state[check.stateKey] : record.text); ok = check.exact ? isDeepStrictEqual(actual, check.value) : matches(actual, check.value); } catch { ok = false; } }
    else if (check.type === "regex") ok = new RegExp(check.pattern, check.flags || "i").test(record.text);
    else throw new Error(`Unsupported check type ${check.type}`);
    results.push({ kind: check.kind || "outcome", ok, detail: check.description || check.type });
  }
  return results;
}

export function blindCards(run) {
  return run.results.filter(r => !r.error).map(record => {
    const test = run.cases.find(c => c.id === record.caseId);
    const resourceTexts = new Set(Object.values(run.variants.find(v => v.id === record.variant)?.resources || {}));
    const trace = record.trace.map(item => item.role === "tool" && resourceTexts.has(item.text) ? { ...item, text: "Instruction resource loaded; variant contents hidden for review." } : item);
    return { id: hash([run.fingerprint, record.id, "blind"]).slice(0, 24), caseId: test.id, mode: run.mode, messages: test.messages, rubric: test.rubric,
      acceptable: test.acceptable || [], forbidden: test.forbidden || [], text: record.text, trace, state: record.state, checks: checks(record, test, run.mode) };
  }).sort((a, b) => a.id.localeCompare(b.id));
}

export function validateReviews(cards, reviews) {
  const byId = new Map(cards.map(card => [card.id, card]));
  const seen = new Set();
  for (const review of reviews) {
    if (!byId.has(review.id) || seen.has(review.id)) throw new Error("Unknown or duplicate blind review id");
    if (!["useful", "acceptable", "missed", "wrong", "uncertain"].includes(review.utility) || !["preserved", "violated", "uncertain"].includes(review.constraints) || !["high", "low"].includes(review.confidence) || typeof review.note !== "string" || !review.note.trim()) throw new Error("Review needs valid utility, constraints, confidence and rationale");
    seen.add(review.id);
  }
  if (seen.size !== cards.length) throw new Error("Every successful trial requires a review");
  return reviews;
}
