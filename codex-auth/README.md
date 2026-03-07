<p align="center"><strong>codex-auth</strong> is a local profile manager for Codex auth accounts.</p>
</br>
---

## Quickstart

### Install and run

```shell
./scripts/install.sh
codex-auth list
codex-auth current
```

## Reference

- Storage:
  - Active auth: `~/.codex/auth.json`
  - Saved profiles: `~/.codex/auth/profiles`
- Core commands:

```shell
codex-auth save personal
codex-auth use personal
codex-auth remove personal
codex-auth watch start
```

- Safety defaults: schema validation, lock file on writes, duplicate account-id prevention, restrictive file permissions.
