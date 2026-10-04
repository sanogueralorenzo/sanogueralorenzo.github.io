# Android Steam

An Android 16+ app being built to run Linux, Steam's Deck interface, and Proton games locally without root. Steam sign-in, the owned-game interface and Superflight rendering work on the validated Samsung S24 (SM-S921U1, Adreno 750). Audio and full game controls are unfinished.

The frontend uses Kotlin and Views/XML. Steam owns authentication, the library, client updates, and game downloads. The initial scope is one ARM64 Adreno device; desktop apps, emulators, external game imports, and frame generation are excluded.

Proposed mobile interface:

![Android Steam interface concept showing the library, search, and game details](docs/android-steam-concept.png)

## Build and try

Use JDK 17 or 21, SDK 36, NDK `28.2.13676358`, and CMake `3.22.1`. Set `ANDROID_HOME` or `sdk.dir` in `local.properties`. Native builds need macOS Command Line Tools or Linux `build-essential libexpat1-dev zstd patch`, plus the usual Bash/curl/archive tools.

```sh
./gradlew :app:assembleDebug
adb install -r app/build/outputs/apk/debug/app-debug.apk
```

Open Android Steam, choose **Install Linux runtime** (98 MB download; 850 MB free storage), then **Start Steam**. First startup installs the matched drivers/session components and downloads Valve's client and remaining runtime; allow several GB of additional internal storage. **Test Linux runtime** verifies command execution. Both minimum and target SDK are 36; the packaged PRoot loader executes Linux programs, with user home stored separately from replaceable runtime files.

Sign in using Steam's QR code and Steam Guard. You can switch apps during authentication and return through Android Steam's ongoing notification. **Stop Steam** in the ongoing notification ends the session. Use touch to navigate and type with Steam’s onscreen keyboard, which opens when selecting search. USB/Bluetooth keyboards and mice use the Android input bridge. Game controls and audio are still being implemented.

Steam prompts to install **Proton Experimental (ARM64)** when it is missing (about 475 MB download / 1.94 GB installed). For a Windows game, select **Android Steam Proton (ARM64)** under its **Properties → Compatibility**. The small tool runs Valve's Steam-managed ARM64 depot directly and excludes the native overlay from Wine to avoid the reproduced Steam IPC crash on relaunch. For Superflight, set **Launch Options** to `-force-d3d11 -screen-width 1280 -screen-height 720 -screen-fullscreen 1`. Other Proton versions and arbitrary game compatibility are unverified.

## Checks

```sh
./gradlew :app:testDebugUnitTest :app:lintDebug :app:assembleDebugAndroidTest
adb install -r app/build/outputs/apk/androidTest/debug/app-debug-androidTest.apk
adb shell am instrument -w -e verifySteam true -e verifySession true -e verifyVulkan true -e verifyInput true \
  com.sanogueralorenzo.androidsteam.test/androidx.test.runner.AndroidJUnitRunner
```

Device checks require an installed runtime and the supported USB-connected S24. Optional `verifyRuntime`, `verifyDisplay`, and `verifyGraphics` arguments enable fresh runtime installation, shared-memory display, and driver installation checks. Downloads are opt-in. Gradle's connected test task uninstalls the app afterward; use the ADB runner above to retain user data.

See [THIRD_PARTY.md](THIRD_PARTY.md) for source pins/licenses [docs/validation.md](docs/validation.md) for the working game configuration and measurements, and [PLAN.md](PLAN.md) for delivery criteria.
