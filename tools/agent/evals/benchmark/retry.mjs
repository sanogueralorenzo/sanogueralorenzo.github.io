import { readJSON, hash, loadSuite } from './suite.mjs';
import { saveJSON } from './artifacts.mjs';

const [suitePath, runPath] = process.argv.slice(2);
if (!runPath) throw new Error('Use retry.mjs suite.json run.json, then run --resume with identical options');
const run = readJSON(runPath), suite = loadSuite(suitePath, run.split);
const fingerprint = hash({ suite: suite.fingerprint, variants: run.variants.map(v => v.id), repeats: run.repeats, concurrency: run.concurrency });
if (run.fingerprint !== fingerprint) throw new Error('Cannot retry after instructions, fixtures, harness, or settings changed');
const failures = run.results.filter(r => r.error);
if (!failures.length) throw new Error('No infrastructure failures to retry');
run.infrastructureRetries = [...(run.infrastructureRetries || []), { sourceHash: hash(run), failures, reason: 'Explicit retry of infrastructure errors only; semantic outputs retained.' }];
run.results = run.results.filter(r => !r.error);
run.complete = false;
saveJSON(runPath, run);
console.log(`Archived ${failures.length} infrastructure failures; semantic outputs unchanged.`);
