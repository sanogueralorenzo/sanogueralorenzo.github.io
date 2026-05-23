# Trace Examples

These fixtures show the minimal capture surface Trace keeps for the MVP.

```shell
cat trace/examples/codex-tool-call.json | trace hook agent --adapter codex --dry-run
cat trace/examples/claude-code-user-prompt.json | trace hook agent --adapter claude-code --dry-run
```

Both commands normalize provider payloads into local session events. Commit memory is still generated from `trace record` or the post-commit hook.
