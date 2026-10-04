# Android Deck

An Android 16+ app being built to run Linux, Steam's Deck interface, and Proton games locally without root. The current development build installs a verified Linux base and checks command execution; Steam, graphics, audio, and game sessions are not available yet.

The initial target is one validated ARM64 Adreno device. The frontend uses Kotlin and Views/XML; Steam will own sign-in, the library, and game downloads. Desktop apps, emulators, external game imports, and frame generation are outside the scope.

## Build and try

Use JDK 17 or 21, Android SDK 36, NDK `28.2.13676358`, and an ARM64 Android 16 device or emulator. Set `ANDROID_HOME` or create `local.properties` with `sdk.dir`. Native builds require Bash, curl, tar, make, and shasum on macOS or Linux x86_64.

```sh
./gradlew :app:assembleDebug
adb install -r app/build/outputs/apk/debug/app-debug.apk
```

Open Android Deck, choose **Install Linux runtime** (78 MB download; 650 MB free internal storage), then **Test Linux runtime**. Runtime files are replaceable; the user home lives separately. Both minimum and target SDK are 36; the packaged PRoot loader executes Linux programs.

## Checks

```sh
./gradlew :app:testDebugUnitTest :app:lintDebug :app:connectedDebugAndroidTest
```

Opt into the real download/execution test with `-Pandroid.testInstrumentationRunnerArguments.verifyRuntime=true`. It installs the pinned Ubuntu ARM64 base and runs Linux twice. Emulator checks cover setup and execution; Adreno graphics and gameplay require the physical device.

See [THIRD_PARTY.md](THIRD_PARTY.md) for source pins and licenses, and [PLAN.md](PLAN.md) for delivery criteria.
