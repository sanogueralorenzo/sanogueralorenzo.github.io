# Voice Engine

The engine is the shared deterministic text pipeline for Voice.

It owns platform-neutral pre-processing, post-processing, edit-command parsing, and guardrails. Platform apps should call the engine instead of reimplementing these rules, so Android, iOS, macOS, and web keep the same behavior for dictation cleanup and rewrite safety.

The engine boundary is:

```text
transcript -> engine preprocess -> platform LLM/runtime -> engine postprocess -> final text
```

Platform apps remain responsible for ASR, UI, keyboard or overlay integration, LLM runtime setup, storage, lifecycle, and telemetry.

Expected engine contents:

- Rule manifests that define enabled rules, phase, order, and parameters.
- A shared rule runtime that applies those manifests.
- Built-in operations for token, span, number, correction, edit, cleanup, and guardrail behavior.
- Conformance fixtures that every platform binding must pass.

