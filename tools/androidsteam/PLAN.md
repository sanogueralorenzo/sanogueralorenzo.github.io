# Android Steam delivery

## Objective and acceptance

Deliver a minimal, measured Arch ARM Steam/ARM64 Proton experience on the S24: native library/settings, Steam QR login, Xbox controls alongside direct touch, reproducible updates and recovery. Preserve accounts, installed games, saves and settings. Users need no Linux desktop or shell. Defer native authentication experiments, Heroic, emulators and speculative frameworks.

Complete only after setup → Steam QR login → live owned library → gameplay → exit/relaunch → restart passes in a release, including cold/warm starts, keyboard/touch/controller input, background/resume and clean shutdown. Keep brief documentation, commit and push to main. Efficiency claims require comparable measurements.

## Ordered work

- [x] Establish source/device baseline and separate verified behavior from experiments.
- [x] Minimize Arch in validated batches; retain required dynamic dependencies/resources and measure downloads, installed bytes and preparation.
- [x] Validate a current reviewed lock, reproducible rebuild and safe update/recovery.
- [x] Compare DroidDeck source/installed APK; retain useful small adaptations with attribution.
- [x] Default Xbox controls, native layout selection, floating sticks/translucent feedback, simultaneous touch and Linux/Windows recognition.
- [x] Finish dependable release launch flow, checks, artifact, brief docs and main delivery.

## Resume state

- Published runtime `androidsteam-runtime-20261005-1`: 242 reviewed packages, required resources retained; independent rebuild SHA-256 `5d9571fd3e463a39dc33f052e693f6dc3069508eb5969cde2f7d8908d1115318`. Archive 162610928 → 99009976 bytes; installed 817661 → 522273 KiB; preparation 72672 → 54473 ms (single samples, network excluded). Replacement/cancel/truncation/interrupted-swap and fresh verified setup/home checks pass. See [validation](docs/validation.md) and [runtime build](docs/runtime-build.md).
- DroidDeck source `05608ac4` and installed APK compared. Adaptive Xbox controls, Linux/Windows recognition, per-pointer direct touch and bounded shutdown adapted with attribution. Native layout selection, floating sticks, translucent feedback and keyboard focus pass. CEF flags offered no clear benefit; defaults retained. V10 fixes a reproduced descriptor identity collision; no general Steam-crash root cause claimed.
- Fixed signed minified APK: 1058217 bytes, SHA-256 `9a934e5df2ec4e94b3b5c8b59192c96e8280ae0ef2b5ad0760b00d566a578c34`; installed hash/v3 signature/no debug probes verified. Runtime/adapters/profiles frozen throughout release acceptance. Build, 27 unit tests/lint, seven device checks (136.926 s) and final three lifecycle/error/diagnostic checks (58.678 s) pass. Loading shows phases/replacement; errors direct users to Library → Play or Profile → Open Steam. Intentional stops do not log failures.
- S24 final release passes two cold Superflight launches (66.64–69.01 / 82.90–85.71 s), three post-Quit launches (121.56–124.11 / 94.72–97.11 / 90.62–93.65 s), Brotato switch (203.68–209.71 s) and SNØ switch (94.05–101.79 s), real gameplay/input/Home/resume/Quit, native IME and live 45-game library/Steam access. Reused clients reproduce exit 139; mandatory client replacement improves observed reliability at substantial startup cost, with no FPS/speedup claim. Final stops reap all Linux in 10.584 / 5.043 s. One cold Superflight menu lacked online stats; unchanged-APK relaunch restored original 22391/8548/ranks without repairs. Cause remains unestablished.
- Accounts, separate home (~18 GiB), five games/saves and original Arrow/Direct touch/WASD+extra-key settings preserved. QR baseline and live ownership already pass. Physical controller/acoustic audio remain unverified; PCM reaches Android. Never clear/uninstall/export auth, restore removed login experiments or add Stop/Retry overlays. Published [androidsteam-20261005-1](https://github.com/sanogueralorenzo/sanogueralorenzo.github.io/releases/tag/androidsteam-20261005-1) targeting source commit `428519bd6b8b3b57dbdcebbc28987b41bfd6136e`, pushed to main. Independently downloaded APK/checksum match the tested hash/size and pass v3 verification; remote tag target verified. Primary checkout fast-forwarded safely. Delivery complete; no pending action. Startup cost, temporary online-stat availability and unverified hardware/audio limits remain documented.

## Requested controller redesign

- Compact original edge layout replaces the inherited automatic arrangement; visual circles and floating sticks are smaller, idle outlines/labels are fainter, and pressed controls brighten. Larger touch targets and the existing input bridge remain. No runtime/session changes.
- Build/lint and four focused S24 input checks pass (87.129 s). Signed APK 1054121 bytes, SHA-256 `efb00c7bd977ab932d3a0b2209469a528cf545aebe8fbf4ca479607920fb195a`; installed hash/v3/no probes verified. Superflight menu 62.46–64.70 s, A outer hit target/analog gameplay/idle-held-pressed-release/pause/Quit pass; original scores/Arrow restored; Stop reaps all Linux in 10.263 s. Presentation sample and limits are in validation. Delivered [androidsteam-20261005-2](https://github.com/sanogueralorenzo/sanogueralorenzo.github.io/releases/tag/androidsteam-20261005-2), source/tag `53dd05c39d37be1a553c50a9d7403e96cc7623df` on main. Independent release download/checksum/v3 verification match the tested candidate. Primary checkout updated; no pending redesign work. Existing game layout choices remain preserved.
