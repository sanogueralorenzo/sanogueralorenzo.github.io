# CLI adapters

Each Slack `commands` entry has `start` and `resume` argument arrays. Use
`{session_id}` as a complete argument in `resume` only. Arguments run directly,
without a shell, in the selected project directory. The prompt arrives on stdin
for both new and resumed requests.

On stdout, return one JSON line:

```json
{"session_id":"native-session-id","answer":"Markdown answer","chat_url":"codex://threads/native-session-id"}
```

`answer` must be nonempty and at most 12,000 characters. `chat_url` is optional;
use an HTTP(S) or `codex://` URL. The bridge adds a lowercase `chat` link
only to the first successful reply in the Slack thread, trimming the answer to
keep the complete reply within the limit.

Flush an optional session checkpoint before doing work:

```json
{"type":"session","session_id":"native-session-id"}
```

This saves the native ID immediately without advancing completed thread context.
The final result and resumed requests must keep that ID. Only a successful turn
advances context; failures can resume the saved session.

Diagnostics belong on stderr. On failure, exit nonzero; optionally emit a final
JSON error such as `{"error":{"code":"auth_required","provider":"Codex"}}`.
The bridge uses known error codes to produce safe, actionable messages and never
posts raw process output. See [error codes](../../bridge/src/slack/errors.rs).

The included Codex adapter runs one turn through a private stdio app-server and
closes it before returning, allowing continuation in the Codex app. It sets the
selected directory on both the chat and turn. Claude uses its native CLI with
`--resume` for follow-ups. Both preserve native model and permission settings.
