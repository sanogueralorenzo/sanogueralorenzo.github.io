# Android Deck

An Android 16+ app being built to run Linux, Steam's Deck interface, and Proton games locally without root. Steam sign-in and the owned-game interface work on the validated Samsung S24 (SM-S921U1, Adreno 750), with touch, mouse, and US keyboard input. Audio and Proton gameplay integration are unfinished.

The frontend uses Kotlin and Views/XML. Steam owns authentication, the library, client updates, and game downloads. The initial scope is one ARM64 Adreno device; desktop apps, emulators, external game imports, and frame generation are excluded.

## Build and try

Use JDK 17 or 21, SDK 36, NDK `28.2.13676358`, and CMake `3.22.1`. Set `ANDROID_HOME` or `sdk.dir` in `local.properties`. Native builds need macOS Command Line Tools or Linux `build-essential libexpat1-dev zstd patch`, plus the usual Bash/curl/archive tools.

```sh
./gradlew :app:assembleDebug
adb install -r app/build/outputs/apk/debug/app-debug.apk
```

Open Android Deck, choose **Install Linux runtime** (98 MB download; 850 MB free storage), then **Start Steam**. First startup installs the matched drivers/session components and downloads Valve's client and remaining runtime; allow several GB of additional internal storage. **Test Linux runtime** verifies command execution. Both minimum and target SDK are 36; the packaged PRoot loader executes Linux programs, with user home stored separately from replaceable runtime files.

Sign in using Steam's QR code and Steam Guard. You can switch apps during authentication and return through Android Deck's ongoing notification. **Stop Steam** in the ongoing notification ends the session. Use touch to navigate and type with Steam’s onscreen keyboard, which opens when selecting search. USB/Bluetooth keyboards and mice use the Android input bridge. Game controls and audio are still being implemented.

## Checks

```sh
./gradlew :app:testDebugUnitTest :app:lintDebug :app:assembleDebugAndroidTest
adb install -r app/build/outputs/apk/androidTest/debug/app-debug-androidTest.apk
adb shell am instrument -w -e verifySteam true -e verifySession true -e verifyVulkan true -e verifyInput true \
  com.sanogueralorenzo.androiddeck.test/androidx.test.runner.AndroidJUnitRunner
```

Device checks require an installed runtime and the supported USB-connected S24. Optional `verifyRuntime`, `verifyDisplay`, and `verifyGraphics` arguments enable fresh runtime installation, shared-memory display, and driver installation checks. Downloads are opt-in. Gradle's connected test task uninstalls the app afterward; use the ADB runner above to retain user data.

See [THIRD_PARTY.md](THIRD_PARTY.md) for source pins/licenses and [PLAN.md](PLAN.md) for delivery criteria.
