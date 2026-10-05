# Arch runtime minimization

S24 SM-S921U1, Android 16, Adreno 750. Accounts, games, saves and profiles stay in the separate home; runtime candidates use staged replacement with recovery. Steam and ARM64 Proton retain their own updates.

## First content batch (2026-10-05)

The official Arch ARM core/extra database hashes still match the reviewed 245-package lock. Package payload downloads for rebuilding total 215003980 bytes; users download the assembled snapshot instead. Required certificates, fonts, graphics, audio, gconv encodings, GTK loaders, notices and provenance remain.

Remove manuals while retaining license/copyright/notice/authorship files; remove locale-generation sources/tools because the session uses glibc's built-in C.UTF-8; remove Mesa's neural-inference API, which the Zink/Turnip path does not use. This batch keeps the package closure unchanged.

| Metric | Original snapshot | Candidate |
| --- | ---: | ---: |
| Base archive bytes | 162610928 | 153760944 |
| Android runtime disk usage, KiB | 817661 | 761463 |
| Installed regular-file bytes, host audit | 794185726 | 742683666 |
| Extraction/cache preparation, ms | 72672 | 67518 |
| Pinned base + drivers + Steam bootstrap downloads, bytes | 526068606 | 517218622 |

Download totals exclude the APK, Steam's subsequent updates, Proton and games. The current Steam bootstrap contributes 357602688 bytes; the matched driver archives contribute 5854990 bytes. Preparation timing is one device sample per configuration, excluding network transfer; it does not establish a repeatable setup/runtime speed improvement.

Two independent builds produce SHA-256 `59bae3f21e0e31375589e02deec5f813398342431b018f16102a3522d87745ab`. The candidate passes isolated extraction, replacement, cancellation, truncated archive failure and interrupted-swap recovery (134.835 seconds), retaining the home sentinel. Ten S24 dependency/font/DNS/audio/rendering/lifecycle checks pass against the activated candidate (31.376 seconds). The source-matching minified release retains the account, five installed games, saved Superflight score and Arrow profile. Superflight renders flight, touch steering, collision and Home/resume; two native Play launches and Quit exits retain the same Steam process. Notification Stop removes all Linux processes. No new snapshot is published yet. The original device runtime remains in `runtime-goal-baseline` for recovery.

## Release regression sample

Same APK, device, Steam/Proton, drivers, D3D11 1280×720 and Arrow overlay; Superflight's generated animated menu differs between runs. Both samples report light thermal throttling, with skin temperature increasing from about 40.2–40.6°C to 40.2–41.2°C. These samples verify rendering/resource behavior, not a speed or memory improvement.

| Metric | Original snapshot | Candidate |
| --- | ---: | ---: |
| Aggregate UID PSS, MiB | 2280.0 | 2341.9 |
| Median CPU, percent of one core | 332.2 | 298.6 |
| Android SurfaceView presentations/s | 33.960 | 29.218 |
| Observed presented frames | 623 | 541 |

CPU uses three 5-second samples after discarding the first `top` sample. Android presentation rate is not engine FPS. The differing generated scene and thermal state prevent interpreting these differences as an effect of removing unused files.

## Reproduce the audit

Extract the bundle onto a case-sensitive filesystem, then run:

```sh
python3 native/runtime/audit.py /path/to/extracted-root /path/to/package-cache > audit.json
```

The audit uses package metadata/file manifests to attribute retained sizes and show dependency paths. Optional `--steam-files names.txt` compares names from Steam's ARM64 binary/library directories. Name overlap establishes neither ABI compatibility nor safe removal. Never include account/configuration/log files in that input.

The largest remaining component is LLVM (about 161 MiB), a direct dependency of Arch's all-driver Mesa library. Deleting it would break graphics. A smaller Zink-only Mesa build requires separate source/build pins and real graphics/gameplay validation. Packaged database/codec/diagnostic tools are further content candidates; dynamic libraries cannot be removed merely because a sampled process did not load them.
