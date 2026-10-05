# Android Steam core reliability

The previous ten-milestone goal is paused. Its prior source state and plan are recoverable in `/Users/mario/.codex/androidsteam-snapshot-dTN2GP` (base `b94e524f2`). Do not resume optional updaters, prewarming, runtime reduction, or client-free launch.

## Current scope

1. Establish an honest complete login path using Steam’s own runtime screen. Preserve every home, session, game, save and profile. Android QR request generation and encrypted storage passed component checks; same-phone approval, token authentication and Linux handoff were never proved.
2. Compare current DroidDeck rendering/input/Steam configuration and measure matched release workloads on S24 before claiming improvements.
3. Validate setup → real login → live owned library → Superflight ARM64 Proton → play/exit/play → app restart, including cold/warm launches and affected game regressions.
4. Fix startup/retry/shutdown/background/input with one session owner; polish native basics.

## Resume

- Worktree: `/Users/mario/.codex/worktrees/androidsteam/sanogueralorenzo.github.io`; branch `sanogueralorenzo/androidsteam`. Never modify the site checkout for this work.
- S24 `RFCWC0YTYGW`, Android 16. Existing debug APK was installed before final native-QR edits; source match unconfirmed. Initial audit found no owned Linux processes. Primary home, existing Steam QR proof home, Android-native QR proof home, runtime and matched graphics remain on-device.
- Baseline choice: remove native approval/deep-link/token handoff from active code and expose Open Steam with Valve’s real login UI. Keep pinned Arch and working game settings. Preserve abandoned source in the external patch/tar snapshot, and preserve all device data including encrypted tokens.
- DroidDeck current upstream fetched at `05608ac4d4da33cfebcc0d6783064ec04ac75aee`; installed 0.3.0 is debug. Direct matched release comparison remains pending.
- Passed: 27 unit tests, lint, debug/test/minified release builds; direct S24 cached online-session/start-stop and private-error regression (2 tests, 39.851s). Replaced debug/test APKs with install -r after an owned-process audit.
- Device now: real Steam login open in the existing isolated Steam QR proof home; a delivered account callback confirms `SIGNED_OUT`. Primary and all proof homes are intact. Awaiting the user’s device-only credentials/Guard interaction; do not replace the APK or send navigation input during login.
- Next: after the user reports Big Picture, require `LINUX_AUTHENTICATED`, live ownership, private game/profile proof and restart. If interaction is deferred, leave this screen/session available and stop dependent work; never export authentication screens, inputs, QR URLs, tokens, auth files, or Steam/SDK logs.
