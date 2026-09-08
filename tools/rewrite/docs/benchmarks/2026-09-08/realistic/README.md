# Realistic rewrite timings

September 8, 2026. Same setup as the [long-message benchmark](../README.md): GPT 5.6 Luna, low (Light) reasoning, Pi 0.85.1 and Codex 0.153.2. Pi requested priority through the benchmark-only request hook; Codex requested Fast. Backend tier acknowledgment was not captured. No installed app or global CLI settings were changed.

Each size was tested three times per CLI, sequentially in Pi/Codex/Codex/Pi/Pi/Codex order. All 18 calls succeeded. Each call used a fresh process and isolated request directory. Timings run through process exit and include Pi auth/config preparation, approximately 0.2 seconds. One-time help/capability checks, native selection capture, and replacement are excluded. All sources are synthetic everyday messages, using the same “Improve readability and phrasing” instruction.

| Selection | Pi median total time | Codex median total time | Median input context: Pi / Codex |
| --- | --- | --- | --- |
| Sentence (18 words) | 5.886 s | 13.301 s | 219 / 2,561 |
| Paragraph (52 words) | 6.602 s | 14.364 s | 257 / 2,597 |
| Message (99 words) | 6.698 s | 13.998 s | 306 / 2,647 |

Pi was approximately 52–56% faster. It still took roughly 6–7 seconds to finish short rewrites. The weak relationship between these short input lengths and total time suggests a substantial fixed delay, but this experiment does not isolate process startup, authentication, network latency, prefill, or model scheduling. It cannot establish how much a persistent process or direct API would save.

Both CLIs reported **zero reasoning tokens in every run**, despite low reasoning being configured. Turning reasoning off alone is therefore not established as a fix. Some Codex runs received 1,792 cached input tokens; Pi reported no cache hits. Input context in the table includes cached tokens, not just newly billed input. Pi cost estimates are not used because the hook does not update its local tier pricing calculation.

Output checks: all sentence rewrites retained tomorrow and Thursday afternoon; paragraph outputs retained the import concern and tomorrow's review; message outputs retained Maya and Thursday. Reviewed sentence/paragraph outputs were nearly identical in meaning and corrected the grammar without adding explanations. The full outputs are stored alongside each source and results.json. This small test does not establish broad quality equivalence.

Reproduce one case (six real model requests):

```sh
python3 ../benchmark.py --source sentence/source.txt --output sentence
```

Replace `sentence` with `paragraph` or `message` for the other cases. Running the command overwrites that case's recorded results. See the parent benchmark for isolation details, tier caveats, provider references, and the Codex diagnostic notices.
