# Trace Workflow Examples

These examples show the local-first workflow Trace expects from coding agents.

## Agent Capture

Install the local hook adapter specs once per repository:

```shell
trace init
trace agent add codex
trace agent add claude-code
trace agent add gemini
trace agent add generic
trace agent check all
```

Adapters write normalized lifecycle events into the git common directory, not the project tree:

```shell
cat trace/examples/codex-tool-call.json | trace hook agent --adapter codex --dry-run
cat trace/examples/codex-tool-call.json | trace hook agent --adapter codex
cat trace/examples/claude-code-user-prompt.json | trace hook agent --adapter claude-code
cat trace/examples/gemini-model-response.json | trace hook agent --adapter gemini
cat trace/examples/generic-validation.json | trace hook agent --adapter generic
```

## Commit Memory

After the code change is committed, generate reviewable memory:

```shell
trace record --validation "npm test"
git add .trace/commits
git commit -m "Commit Trace memory"
```

The committed Markdown is the canonical memory. Raw session events and checkpoint payloads stay outside normal branch history unless `refs/trace/checkpoints` is explicitly pushed.

## Review And CI

Use committed memories for handoff and review:

```shell
trace show HEAD
trace review --output trace-review.md
trace search --field agents "codex"
trace search --field lifecycle "validation"
trace search --field decisions "storage"
trace search --field decisions "storage" --output trace-search.txt
trace search --field handoff "preserve"
trace session recap example-session --field handoff --output trace-session-recap.md
trace recall "storage" --output trace-recall.md
trace pr-body main..HEAD
trace pr-body main..HEAD --output trace-pr-body.md
trace release-notes v1.0.0..HEAD
```

Use CI to prevent missing memory and transcript leaks:

```shell
trace redact preview --text 'PROJECT-ORION token=secret'
trace ci main..HEAD --agents --checkpoints
```
