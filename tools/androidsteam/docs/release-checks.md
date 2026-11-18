# Release acceptance on the S24

Keep the APK, Arch snapshot, native adaptations, Steam/Proton builds and game profiles fixed for a run. Record the APK SHA-256, device/OS, public game/build IDs and original profiles before testing. Install updates with `adb install -r` after stopping Steam; never clear/uninstall the app. Preserve the separate home, accounts, saves and installed games.

## Candidate gate

Build debug/test and minified release, run unit tests/lint, and verify the signed APK with `apksigner verify`. Check the archive has no debug probes and its launch script matches source. Run the focused opt-in Session/Input/Xbox/ControllerGameplay classes using `am instrument`; inspect the JUnit result, because an assertion failure can still give a successful shell exit. Do not use Gradle's connected task: it uninstalls afterward. Stop/reap all Linux processes before installing the signed release. Verify its installed hash and absence of DEBUGGABLE.

## Fixed release flow

1. Native Setup reaches Ready with the published snapshot. Check Steam QR login when login is required; use the existing account during repeat runs. Refresh the native library against the live local client. Cached/artwork/manifests alone cannot pass ownership.
2. Native Play → **usable game menu** → actual movement/input → in-game Quit → native details. A surface frame or tracked process alone is insufficient. Record elapsed time from Play and screenshot sampling interval; do not export screens containing QR/account data.
3. Repeat the same game twice after Quit. Confirm each replacement reaps the prior Steam/game processes, starts a new Steam PID and reaches a usable menu. Check saved score/profile persistence. Repeat cold Play after notification Stop.
4. Switch Superflight → Brotato → SNØ through the native library. Enter gameplay for each, exercise keyboard and direct touch, Home/resume, pause/retry and Quit. For Xbox, check A/analog movement, held/released floating stick, pressed feedback and touch outside controls. Restore original selections after checks.
5. Refresh the live library during a paused game, open the session again and confirm the same client/game resume. Stop through the notification and verify all app-owned Linux processes are reaped. Reopen Steam, check retained login/live library, then stop cleanly again.
6. Verify native loading phase/spinner and actionable error behavior. Inject audio failure only with the debug lifecycle fixture; it must remove loading progress, retain Library navigation and release display/audio/processes. Final gameplay uses the signed APK without probes or injected failures.

If a menu times out, a client exits, or data/profile changes unexpectedly, fail the candidate and record that reproduced case before changing code. Rebuild means a new hash and a fresh affected acceptance run. Report startup cost even when replacement improves reliability.

## Sanitized failure evidence

Record candidate hash, public game ID, attempted flow, observed menu/error stage, elapsed bounds, numeric exits and whether cleanup/retry worked. The owner emits only a controlled cause/phase, public app ID and numeric exits under `SteamSession`; intentional stop/replacement is excluded. Capture only that tag, for example:

```sh
adb logcat -d -v brief -s SteamSession:E '*:S'
```

Never collect full logcat/Steam output, account IDs, tokens, cookies, environment/profile dumps or crash heaps. A screenshot must be checked locally for sign-in/account content before sharing. Existing exit-139 evidence supports the replacement policy; it does not establish an upstream root cause. Current results and limitations are in [device validation](validation.md).
