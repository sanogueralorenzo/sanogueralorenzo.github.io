# Android Deck

An Android 16+ app being built to run Linux, Steam's Deck interface, and Proton games locally without root. The current development build installs a verified Linux base and checks command execution; Steam client installation and real-device graphics are covered by opt-in checks; Steam sessions, audio, and games are not available yet.

The initial target is one validated ARM64 Adreno device. The frontend uses Kotlin and Views/XML; Steam will own sign-in, the library, and game downloads. Desktop apps, emulators, external game imports, and frame generation are outside the scope.

## Build and try

Use JDK 17 or 21, Android SDK 36, NDK `28.2.13676358`, CMake `3.22.1`, and an ARM64 Android 16 device or emulator. Set `ANDROID_HOME` or create `local.properties` with `sdk.dir`. Native builds require Bash, curl, tar, make, shasum, ar, patch, a host C compiler, and Expat development headers on macOS or Linux x86_64 (macOS Command Line Tools; Linux `build-essential libexpat1-dev zstd patch`).

```sh
./gradlew :app:assembleDebug
adb install -r app/build/outputs/apk/debug/app-debug.apk
```

Open Android Deck, choose **Install Linux runtime** (98 MB download; 850 MB free internal storage), then **Test Linux runtime**. Runtime files are replaceable; the user home lives separately. Both minimum and target SDK are 36; the packaged PRoot loader executes Linux programs.

## Checks

```sh
./gradlew :app:testDebugUnitTest :app:lintDebug :app:connectedDebugAndroidTest
```

Opt into the real download/execution test with `-Pandroid.testInstrumentationRunnerArguments.verifyRuntime=true`. It installs the pinned Ubuntu ARM64 base and runs Linux twice. Use the USB-connected S24 for current device tests; Adreno graphics and gameplay require the physical device.

After installing the runtime, `-Pandroid.testInstrumentationRunnerArguments.verifyDisplay=true` enables the Linux Wayland display check: actual surface pixels, failed-start recovery, live-client shutdown, and display restart. This development check uses shared-memory frames. Gradle's connected test task removes the app and its runtime afterward.

`-Pandroid.testInstrumentationRunnerArguments.verifyGraphics=true` installs the pinned candidate Android/Linux Turnip pair (6 MB download) and checks Linux driver loading with its verified library bundle. This setup is currently exercised through the integration test.

On the supported Adreno device, after runtime setup, `-Pandroid.testInstrumentationRunnerArguments.verifyVulkan=true` installs graphics if needed and exercises the native dma-buf bridge with a real Linux Vulkan client, Android pixel readback, surface reattachment, and two sessions. This check passes on the Android 16 Samsung S24 (SM-S921U1, Adreno 750), including repeated rendering and restart. It is skipped unless requested. The native bridge is not yet connected to the app's session UI.

`-Pandroid.testInstrumentationRunnerArguments.verifySteam=true` downloads the pinned stable ARM64 Steam client directly from Valve (358 MB; 2.5 GB free storage), verifies each component, and checks extraction, client links, retry, and user-data preservation. Installation passes on the S24; the Deck session and sign-in screen are still being integrated. The client is not included in the APK.

`-Pandroid.testInstrumentationRunnerArguments.verifySession=true` enables session-component installation/dependency checks and the Gamescope rendering probe. The current rendering probe stops because presentation-time feedback is still missing; Steam sign-in is not ready. The user will authenticate once the interface is available.

See [THIRD_PARTY.md](THIRD_PARTY.md) for source pins and licenses, and [PLAN.md](PLAN.md) for delivery criteria.
