# AEOLIAN

AEOLIAN is a stylized 3D downhill roguelite about descending an impossible,
wind-rebuilt mountain on an all-terrain windboard.

> The wind makes a new mountain every time.

## Production status

Phases 0 and 1 passed on 2026-08-23. The project is in **Phase 2 — Movement
validation**. The foundation boots, persists settings/profile data, separates
seeded RNG domains, diagnoses failures, runs focused tests, and cross-packages for
Windows/Linux. No movement controller exists yet, so this is not a gameplay
prototype or vertical slice. Current stage-gate status and the prioritized backlog
live in [docs/production.md](docs/production.md).

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

From this folder, run the complete foundation suite with `./scripts/check.sh` and
cross-export packaging with `./scripts/export-smoke.sh` (exact-version Godot export
templates are required).

## Living documentation

- [Game design](docs/game-design.md)
- [Technical architecture](docs/technical-design.md)
- [Production state, roadmap, backlog, decisions, and risks](docs/production.md)
- [Performance budgets and test plan](docs/quality-plan.md)
- [Asset, licensing, and placeholder register](docs/assets-and-licenses.md)
- [Release-candidate checklist](docs/release.md)
- [Initial project audit](docs/phase-0-audit.md)
- [Phase 1 foundation gate record](docs/phase-1-foundation.md)
