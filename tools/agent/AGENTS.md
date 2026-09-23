# Agent

- Make one complete feature change at a time. Keep ownership clear, entry points thin, and code straightforward. Remove replaced paths; share helpers only when duplication is real.
- Do not add tests unless requested. Run a focused check for changed behavior, then commit and push to `main` without a PR.
- Agent is pre-release. When behavior changes, delete the replaced implementation, flags, aliases, migrations, compatibility branches, tests, and copy instead of preserving them.
- Keep only recovery behavior that is part of the current product design; never use silent fallback to another login flow, backend, model, credential store, or protocol shape.
- Keep `README.md` as a short product quickstart. Put necessary technical contracts in focused docs or code, not in the README.
- Keep clients thin. The Agent runtime coordinates Agent sessions, routing, queues, memory, and saved transcripts; Codex App Server owns model execution, persistent Codex task context, and Codex tools. Keep native Codex capabilities, including Computer Use, in the shared Codex App Server path rather than implementing replacements in Agent.
- Keep one active run per Agent session and one writer for a code change at a time. Open-in-Codex and Agent navigation should continue to the same persistent Codex task when supported, without creating a duplicate task or replaying the conversation.
