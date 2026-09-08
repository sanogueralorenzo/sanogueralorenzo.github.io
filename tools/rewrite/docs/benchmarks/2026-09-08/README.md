# Pi versus Codex: long rewrite

Measured September 8, 2026 on the same Mac, using Pi 0.85.1 and Codex CLI 0.153.2. This is a small practical benchmark, not a general model-speed guarantee.

## Result

| Measurement | Pi | Codex CLI |
| --- | --- | --- |
| Model | GPT 5.6 Luna | GPT 5.6 Luna |
| Reasoning | low (Light) | low (Light) |
| Requested service tier | priority | fast (catalog maps to priority) |
| Median elapsed, including Pi auth/setup | 17.610 s | 24.255 s |
| Elapsed range, three retained runs | 17.460–17.713 s | 23.824–26.669 s |
| Median total input context | 1,237 tokens | 3,579 tokens |
| Output tokens, retained runs | 1,015 / 1,026 / 1,007 | 1,016 / 955 / 1,013 |
| Cached input, retained runs | 0 / 0 / 0 | 0 / 0 / 1,792 |

Pi finished about **27.4% sooner** and used **65.4% less total input context**. Context here means input tokens reported by the provider, including cached input, not maximum context-window capacity. Pi reports cached input separately, so total input is `input + cacheRead + cacheWrite`; all Pi cache counters were zero. Codex's `input_tokens` already includes its cached portion. Output counts are reported counters and include reasoning according to each CLI's usage schema.

## Method

The input is a synthetic 926-word internal update in [source.txt](source.txt), not private user material. Both receive the same source JSON, `Improve readability and phrasing.` instruction, and Rewrite's production system prompt. Both use Luna and low reasoning. No project context, tools, conversations, or user customization is intentionally loaded. Codex uses the previous Rewrite adapter's isolation flags and a replacement instructions file. Pi uses the new adapter's isolated temporary configuration and auth-resolution strategy.

Pi has no native `--fast` flag or service-tier setting in its CLI/settings interface. For this benchmark only, a single explicit extension uses Pi's documented `before_provider_request` hook to set `service_tier: "priority"`. All extension discovery stays disabled. Its audit confirms that each outgoing payload requested priority and contained zero tools. This extension is **not installed into Rewrite or the user's global Pi configuration**. The installed Rewrite app's speed setting is unchanged.

Codex receives `-c service_tier="fast" --enable fast_mode`. Its installed Luna catalog advertises Fast as priority. These are requested tiers; neither captured CLI event stream established which tier the backend ultimately served. No claim is made about actual priority billing. Pi's estimated cost fields are not used for comparison because the payload hook does not update its local cost estimator.

The runs initially alternated in pairs: Pi, Codex, Codex, Pi, Pi, Codex. Run 6 was replaced with a separate isolated Codex run 7 because a short diagnostic may have overlapped with run 6. Run 6 remains in the raw results and is explicitly excluded. Summary samples are Pi runs 1/4/5 and Codex runs 2/3/7. All model calls completed successfully. The diagnostic notices were about the disabled code-mode host and the experimental skill-discovery flag, not failed model requests or tool execution.

Timing covers process launch through completed response/process exit. Pi totals also include resolving its existing credential and preparing the disposable directory (about 0.2 s). One-time app CLI capability checks are excluded. This is not time-to-first-token, and it does not include macOS selection capture or text replacement. Responses were not constrained to an exact output length. Three samples are too few to distinguish all network, caching, model-generation, and service-load effects.

## Output review

All seven long outputs preserved the named owners, September 18 and September 23, the $4,500 budget, and both URLs. Representative Pi and Codex outputs also retained the internal-only restriction, tentative dates and assignments, scope exclusions, and instruction not to promise a launch. Both improved grammar and readability without answering the questions inside the source. Pi sometimes turned the ownership paragraph into bullets. This is a spot-check of one message, not a comprehensive quality evaluation.

See [results.json](results.json) for per-run measurements and the numbered text files for complete outputs. Re-run `python3 benchmark.py` only intentionally: it makes six real provider requests using existing sign-ins and overwrites the benchmark outputs. Credentials are handled only in memory and mode-600 files inside automatically removed temporary directories.

References: [Codex Fast mode](https://learn.chatgpt.com/docs/agent-configuration/speed), [Pi request hook](https://github.com/earendil-works/pi/blob/main/packages/coding-agent/docs/extensions.md#before_provider_request), [Pi JSON events](https://github.com/earendil-works/pi/blob/main/packages/coding-agent/docs/json.md). Installed CLI help, provider source, and Luna catalog were inspected as well.
