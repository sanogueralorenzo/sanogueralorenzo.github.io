# Agent

- Agent is pre-release. When behavior changes, delete the replaced implementation, flags, aliases, migrations, compatibility branches, tests, and copy instead of preserving them.
- Keep only recovery behavior that is part of the current product design; never use silent fallback to another login flow, backend, model, credential store, or protocol shape.
- Keep `README.md` as a short product quickstart. Put necessary technical contracts in focused docs or code, not in the README.
- Keep all clients thin and make the shared Agent runtime the sole owner of sessions, memory, routing, tools, and recovery.
