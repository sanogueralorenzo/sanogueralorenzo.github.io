# Amarchy

An Android home for an Android-adapted ARM64 Omarchy desktop. Android 16+ and ARM64 are the initial baseline. Emulator checks exercise a real Hyprland terminal through Mesa software rendering without root. Omarchy configuration, applications and the normal one-action desktop launch remain under development.

## Build

Use JDK 17 or 21, Android SDK 36, NDK `29.0.14206865`, CMake `3.22.1`, Python 3.11+, and macOS Command Line Tools or Linux build tools with Expat and a C++23 host compiler. Set `ANDROID_HOME` or `sdk.dir` in `local.properties`.

```sh
./gradlew :app:assembleDebug :app:assembleDebugAndroidTest :app:lintDebug
adb install -r app/build/outputs/apk/debug/app-debug.apk
adb install -r app/build/outputs/apk/androidTest/debug/app-debug-androidTest.apk
adb shell am instrument -w com.sanogueralorenzo.amarchy.test/androidx.test.runner.AndroidJUnitRunner
```

The build downloads checksum-pinned ARM64 packages and bundles the environment in the APK. First use extracts it into private storage; the user home remains separate. No root, separate Linux installer, or runtime download is required.

Maintainers explicitly refresh package inputs with `python3 runtime/lock.py`, review the lock, and rebuild. Builds never refresh the lock automatically. See [third-party notices](THIRD_PARTY.md) for source pins and licenses.
