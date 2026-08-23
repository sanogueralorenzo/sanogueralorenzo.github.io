# AEOLIAN

AEOLIAN is a stylized 3D downhill roguelite about descending an impossible,
wind-rebuilt mountain on an all-terrain windboard.

> The wind makes a new mountain every time.

## Production status

The project is in **Phase 0 — Project audit and preproduction**. The repository
started as a blank Godot 4.7 Forward+ project on 2026-08-23. Current stage-gate
status and the prioritized backlog live in [docs/production.md](docs/production.md).

No prototype, vertical slice, or content-complete build is considered the
finished game. The release-candidate definition is recorded in
[docs/release.md](docs/release.md).

## Open the project

Use Godot 4.7.2 or a compatible stable 4.7 patch release:

```sh
godot --editor --path games/aeolian
```

Headless project validation:

```sh
godot --headless --path games/aeolian --editor --quit-after 2
```

## Living documentation

- [Game design](docs/game-design.md)
- [Technical architecture](docs/technical-design.md)
- [Production state, roadmap, backlog, decisions, and risks](docs/production.md)
- [Performance budgets and test plan](docs/quality-plan.md)
- [Asset, licensing, and placeholder register](docs/assets-and-licenses.md)
- [Release-candidate checklist](docs/release.md)
- [Initial project audit](docs/phase-0-audit.md)

