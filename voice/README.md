## Intro

**Voice** is an Android on-device voice keyboard (IME) with local ASR and local rewrite/edit.

## Quickstart

### Build and install debug app

```shell
./gradlew :app:installDebug
```

## Reference

- Package: `com.sanogueralorenzo.voice`
- Runtime model:
  - Dictation: Moonshine ASR (local)
  - Rewrite/Edit: LiteRT-LM (local)
- Setup flow:
  1. Open app.
  2. Download models.
  3. Grant mic permission.
  4. Enable/select Voice keyboard.
- Optional eval scripts:

```shell
scripts/prompt_eval.sh --prompt-file examples/prompt_eval/prompt.txt --cases-file examples/prompt_eval/cases.jsonl --report-file .cache/prompt_eval/report.txt --json-report-file .cache/prompt_eval/report.json
scripts/prompt_ab_optimize.sh --prompt-a-file scripts/prompt_a.json --prompt-b-file scripts/prompt_b.json --dataset-file scripts/dataset.jsonl
```
