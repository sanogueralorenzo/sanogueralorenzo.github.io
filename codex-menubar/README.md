## Intro

**codex-menubar** is a macOS menu bar app that orchestrates local Codex CLIs.

---

## Quickstart

### Install and launch

```shell
./scripts/install.sh
```

## Reference

- App path: `/Applications/Codex Menu Bar.app`
- Integrates with:
  - `codex-auth` (required)
  - `codex-remote` (optional)
- On launch, it starts auth sync through `codex-auth watch start`.
