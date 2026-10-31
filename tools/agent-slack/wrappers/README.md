# Command wrappers

[Codex](codex.py) and [Claude](claude.py) translate their native CLI output into Agent Slack's command format. They inherit native model, reasoning, and permission settings. Slack credentials are removed from command environments.

To use another tool, configure its `start` and `resume` argument arrays in `.env` (see the [example](../.env.example)). Executables are resolved from the project root or `PATH` at startup, then run in the selected workspace. Arguments are passed without a shell; a standalone `{session_id}` argument in `resume` is replaced with the saved ID.

Commands read the prompt from stdin and write one JSON object to stdout:

```json
{"session_id":"saved-session-id","answer":"Final answer for Slack"}
```

Both fields must be nonempty strings; resume must return the same session ID. Answers use Slack Markdown, up to 12,000 characters. Write diagnostics to stderr and exit nonzero on failure.

A new session receives the prior Slack thread and current request. Resuming receives only new messages, skipping answers already known to that session. The current keyword is stripped; other participants' messages are context. Keywords with identical start/resume commands share the thread's session.
