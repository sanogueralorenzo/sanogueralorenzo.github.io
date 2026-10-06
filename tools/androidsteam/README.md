# Android Steam

Run Steam’s Deck interface and ARM64 Proton games locally on Android 16+, without root or a Linux desktop. The native library, search, game details and settings use Steam’s actual licenses and installed-game data. Tested on Samsung S24 (SM-S921U1, Adreno 750); broader device/game compatibility is unverified.

## Install and use

Download the [development-signed release APK](https://github.com/sanogueralorenzo/sanogueralorenzo.github.io/releases/tag/androidsteam-20261005-2) and install it with Android’s package installer. Install updates over the existing app to preserve accounts, games and saves.

Open Android Steam and choose **Profile → Setup → Download**, then **Start Steam**. Download prepares the pinned Arch base (94.4 MiB), matched graphics, audio/session components and Valve’s client; allow several GB of internal storage. Its ongoing notification supports cancellation, and retry keeps completed components. Steam sign-in is still required for account-dependent prerequisites and games. User data is stored separately from replaceable runtime files.

Choose **Open Steam** and complete Steam’s own QR sign-in on the device. Return with the **Library** icon and tap **Refresh library**. The local client supplies available licenses; files and artwork do not establish ownership. The last license check identifies offline cached results. Native Library/Search/Downloads show actual manifest state and cached play history. Steam manages installs, updates, cloud prompts and achievements.

Touch navigates Steam and opens its onscreen keyboard. USB/Bluetooth keyboard and mouse events pass through Android. You can switch apps and return through the ongoing notification; **Stop Steam** ends the session. Audio uses Android AudioTrack and mutes while hidden.

New games default to **Xbox controller** controls. Our compact edge layout uses faint buttons with larger touch targets and brighter pressed feedback. Small floating sticks appear while touching their activation areas and disappear on release. The input bridge retains the adapted DroidDeck implementation with [source attribution](THIRD_PARTY.md). Touch outside controls reaches Steam or the game, including while a control is held. Choose **Xbox controller**, **Direct touch**, **Arrow keys** or **WASD** from the gamepad icon or native **Game settings**; existing selections are preserved. Keyboard layouts offer movement/Escape/Space/Enter and up to four optional P/R/Ctrl/Shift/C/X keys. Android gamepad events use the Xbox bridge; physical hardware remains untested.

Steam prompts to install **Proton Experimental (ARM64)** when it is missing (about 475 MB download / 1.94 GB installed). For a Windows game, select **Android Steam Proton (ARM64)** under its **Properties → Compatibility**. The small tool runs Valve's Steam-managed ARM64 depot directly and excludes the native overlay from Wine to avoid the reproduced Steam IPC crash on relaunch. Other Proton versions and arbitrary game compatibility are unverified.

**Game settings** edits Proton, arguments, environment (`NAME=value` per line) and controls. **Play** starts or reuses one Steam session; edited launch settings or another game launch after gameplay restart the idle client to avoid a reproduced ARM-client relaunch crash. This adds Steam startup time; the native screen shows replacement/loading phases. If a session fails, tap **Library → Play** or **Profile → Open Steam** to retry after cleanup. Close the current game before launching another. Exiting a game opened through Play returns to native details. **Manage in Steam** exposes required prompts.

Tested configurations: Superflight uses **Android Steam Proton (ARM64)** and `-force-d3d11 -screen-width 1280 -screen-height 720 -screen-fullscreen 1`; Xbox and Arrow controls work. Brotato uses the same tool and `--video-driver GLES2`, with Direct touch menus/WASD movement. SNØ uses the same tool, WASD, no arguments, optional P/R keys. See [device validation](docs/validation.md) for startup limits and evidence. Native Linux game builds and other Proton versions remain unverified.

## Build

Use JDK 17 or 21, SDK 36, NDK `28.2.13676358`, and CMake `3.22.1`. Set `ANDROID_HOME` or `sdk.dir` in `local.properties`. Native builds need macOS Command Line Tools or Linux `build-essential libexpat1-dev zstd patch`, plus the usual Bash/curl/archive tools.

```sh
./gradlew :app:assembleDebug
adb install -r app/build/outputs/apk/debug/app-debug.apk
```

Both minimum and target SDK are 36. The packaged PRoot loader executes Linux programs; **Test Linux runtime** in Setup checks execution.

## Runtime updates

The Linux base is an Arch ARM snapshot assembled from `native/runtime/seeds.txt` and its checksum-pinned dependency lock. It excludes the generic image’s kernel/firmware, development outputs and manuals; required resources, licenses and package provenance remain. Steam, games and saves live in a separate home directory.

See [runtime build and update instructions](docs/runtime-build.md) for the reviewed lock, pinned Zink source/toolchain, independent rebuild and safe publication workflow. Users receive validated snapshots through app updates; installation checks staging before replacement and recovers interrupted swaps.

## Checks

```sh
./gradlew :app:testDebugUnitTest :app:lintDebug :app:assembleDebugAndroidTest
adb install -r app/build/outputs/apk/androidTest/debug/app-debug-androidTest.apk
adb shell am instrument -w -e verifySteam true -e verifySession true -e verifyVulkan true -e verifyInput true -e verifyAudio true \
  com.sanogueralorenzo.androidsteam.test/androidx.test.runner.AndroidJUnitRunner
```

Device checks require an installed runtime and the supported USB-connected S24. Opt-in `verifyControllerGame` checks rendered controls through Windows x64 XInput with installed Superflight. Other checks cover live licenses, launch profiles, setup and snapshot recovery; see the test classes and [validation](docs/validation.md). Use the ADB runner above: Gradle’s connected task uninstalls the app afterward. APK replacement with `install -r` preserves user data.

See [THIRD_PARTY.md](THIRD_PARTY.md) for source pins/licenses, [docs/validation.md](docs/validation.md) for the working game configuration and measurements, and [release checks](docs/release-checks.md) for the repeatable acceptance procedure.
