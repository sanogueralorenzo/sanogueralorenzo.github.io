# Android Steam

An Android 16+ app being built to run Linux, Steam's Deck interface, and Proton games locally without root. Steam sign-in, the owned-game interface and Superflight, Brotato and SNØ gameplay with digital touch controls work on the validated Samsung S24 (SM-S921U1, Adreno 750). Game audio reaches Android output; the native launcher and broader game compatibility are unfinished.

The frontend uses Kotlin and Views/XML. Steam owns authentication, the library, client updates, and game downloads. The initial scope is one ARM64 Adreno device; desktop apps, emulators, external game imports, and frame generation are excluded.

Proposed mobile interface:

![Android Steam interface concept showing the library, search, and game details](docs/android-steam-concept.png)

## Build and try

Use JDK 17 or 21, SDK 36, NDK `28.2.13676358`, and CMake `3.22.1`. Set `ANDROID_HOME` or `sdk.dir` in `local.properties`. Native builds need macOS Command Line Tools or Linux `build-essential libexpat1-dev zstd patch`, plus the usual Bash/curl/archive tools.

```sh
./gradlew :app:assembleDebug
adb install -r app/build/outputs/apk/debug/app-debug.apk
```

Open Android Steam, choose **Install Linux runtime** (156 MiB download; 1.5 GB free storage), then **Start Steam**. First startup installs the matched drivers/session components and downloads Valve's client and remaining runtime; allow several GB of additional internal storage. **Test Linux runtime** verifies command execution. Both minimum and target SDK are 36; the packaged PRoot loader executes Linux programs, with user home stored separately from replaceable runtime files.

Sign in using Steam's QR code and Steam Guard. You can switch apps during authentication and return through Android Steam's ongoing notification. **Stop Steam** in the ongoing notification ends the session. Use touch to navigate and type with Steam’s onscreen keyboard, which opens when selecting search. USB/Bluetooth keyboards and mice use the Android input bridge. Linux game audio plays through Android AudioTrack and mutes while the session is hidden.

During a game, tap the small gamepad icon to choose **Direct touch**, **Arrow keys** or **WASD**, saved separately for that game. The keyboard layouts add a movement stick and Escape/Space/Enter buttons. Android controller left-stick/D-pad and A/B/X events map to the same digital keyboard controls; analog Xbox emulation and right-stick aiming are unsupported. Controller events passed Linux integration checks; a physical gamepad has not been tested.

Steam prompts to install **Proton Experimental (ARM64)** when it is missing (about 475 MB download / 1.94 GB installed). For a Windows game, select **Android Steam Proton (ARM64)** under its **Properties → Compatibility**. The small tool runs Valve's Steam-managed ARM64 depot directly and excludes the native overlay from Wine to avoid the reproduced Steam IPC crash on relaunch. Other Proton versions and arbitrary game compatibility are unverified.

**Game settings** edits an installed game's Proton choice, arguments, environment (`NAME=value` per line) and controls. Saved launch settings apply before the next Steam startup; stop Steam from its notification and start it again. For Superflight, choose **Android Steam Proton (ARM64)**, **Arrow keys**, and arguments `-force-d3d11 -screen-width 1280 -screen-height 720 -screen-fullscreen 1`. Brotato gameplay was also validated with that Proton tool, **WASD**, and `--video-driver GLES2`; startup currently takes minutes. Switch to **Direct touch** when the movement overlay covers menu buttons. The app preserves unrelated Steam configuration. A listed Linux build does not establish that its native execution path works on Android; Steam default/native paths are marked unverified. Complex custom launch commands remain editable in Steam.

## Runtime updates

The Linux base is an Arch ARM snapshot assembled from `native/runtime/seeds.txt` and its checksum-pinned dependency lock. It excludes the generic image’s kernel/firmware, development outputs and manuals; required resources, licenses and package provenance remain. Steam, games and saves live in a separate home directory.

To update, run `python3 native/runtime/update.py`, review the package/source diff, then `bash native/runtime/build.sh /tmp/androidsteam-runtime`. The build needs Python 3, XZ, and a case-sensitive filesystem; on macOS set `TMPDIR` to a case-sensitive APFS volume. Retain the verified package cache because Arch's rolling mirrors can remove older versions. Validate the bundle and the Steam/game baseline on the S24, publish a new fixed release, and update `RuntimeInstaller`’s version, URL, byte count and SHA-256. Installation checks the staged runtime before replacement and recovers an interrupted swap. Users receive the tested bundle through app updates.

## Checks

```sh
./gradlew :app:testDebugUnitTest :app:lintDebug :app:assembleDebugAndroidTest
adb install -r app/build/outputs/apk/androidTest/debug/app-debug-androidTest.apk
adb shell am instrument -w -e verifySteam true -e verifySession true -e verifyVulkan true -e verifyInput true -e verifyAudio true \
  com.sanogueralorenzo.androidsteam.test/androidx.test.runner.AndroidJUnitRunner
```

Device checks require an installed runtime and the supported USB-connected S24. Optional `verifyRuntime`, `verifyDisplay`, and `verifyGraphics` arguments enable fresh runtime installation, shared-memory display, and driver installation checks. Downloads are opt-in. `verifyRuntimeSnapshot` tests a checksum-matching `/data/local/tmp/androidsteam-runtime.tar.xz` in a separate validation directory, including replacement, cancellation, failure and recovery. Gradle's connected test task uninstalls the app afterward; use the ADB runner above to retain user data.

See [THIRD_PARTY.md](THIRD_PARTY.md) for source pins/licenses, [docs/validation.md](docs/validation.md) for the working game configuration and measurements, and [PLAN.md](PLAN.md) for delivery criteria.
