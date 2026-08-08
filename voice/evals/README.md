# Voice Evaluations

Shared prompts, datasets, and runners for evaluating Voice cleanup and rewrite behavior.

- `dataset.jsonl` is the cross-platform benchmark dataset used by the apps.
- `prompt_a.json` is the current runtime prompt; `prompt_b.json` is the challenger.
- `prompt_eval_android.py` runs the source-of-truth benchmark on a connected Android device.
- `prompt_eval.sh` provides an optional host smoke test.

Run tools from any directory; their default assets resolve from this folder.
