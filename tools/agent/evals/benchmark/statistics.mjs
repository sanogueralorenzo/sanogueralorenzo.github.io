export function mean(values) { return values.length ? values.reduce((a, b) => a + b, 0) / values.length : null; }
export function percentile(values, p) {
  if (!values.length) return null;
  const sorted = [...values].sort((a, b) => a - b);
  return sorted[Math.max(0, Math.ceil(p * sorted.length) - 1)];
}
export function pairedInterval(rows, baseline, candidate, samples = 4000) {
  const families = new Map();
  const cases = new Map();
  for (const row of rows) {
    const key = `${row.family}\0${row.caseId}`;
    const value = cases.get(key) || { family: row.family, values: {} };
    (value.values[row.variant] ||= []).push(row.score);
    cases.set(key, value);
  }
  for (const value of cases.values()) {
    if (!value.values[baseline] || !value.values[candidate]) continue;
    const delta = mean(value.values[candidate]) - mean(value.values[baseline]);
    (families.get(value.family) || (families.set(value.family, []), families.get(value.family))).push(delta);
  }
  const deltas = [...families.values()].map(mean);
  if (!deltas.length) return { meanDifference: null, low: null, high: null, pairedFamilies: 0, method: "No certain paired families; comparison is unresolved." };
  let seed = 104729;
  const random = () => { seed = (Math.imul(seed, 1664525) + 1013904223) >>> 0; return seed / 4294967296; };
  const draws = [];
  for (let i = 0; i < samples; i++) draws.push(mean(deltas.map(() => deltas[Math.floor(random() * deltas.length)])));
  return { meanDifference: mean(deltas), low: percentile(draws, .025), high: percentile(draws, .975), pairedFamilies: deltas.length,
    method: "Equal-weight family means; paired family bootstrap, 95% interval. Describes these cases, not guaranteed production performance." };
}
