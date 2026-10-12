# Amarchy

An Android host being built for the most complete practical upstream ARM64 Omarchy desktop. Android 16+ and ARM64 are the initial baseline. One action prepares the bundled environment and opens a real Hyprland desktop. Mesa supplies software rendering without root or an Adreno requirement. Upstream shell, menus, themes and the broader application set are being integrated; the current build still uses selected defaults.

Choose **Get started** once, then use **Apps** for Terminal, Files, Neovim and Chromium. **Keyboard** opens or hides Android's keyboard; the desktop resizes above it. **Keys** provides shortcuts and Android clipboard paste. Touch clicks/drags, two-finger movement scrolls, and a keyboard/mouse can operate the desktop. **Home** keeps it running; **Close desktop** stops it. The separate home preserves projects and settings across app/runtime updates. Audio and release acceptance are still in development.

## Build

Use JDK 17 or 21, Android SDK 36, NDK `29.0.14206865`, CMake `3.22.1`, Python 3.11+, and macOS Command Line Tools or Linux build tools with Expat and a C++23 host compiler. Set `ANDROID_HOME` or `sdk.dir` in `local.properties`.

```sh
./gradlew :app:assembleDebug :app:assembleDebugAndroidTest :app:lintDebug
adb install -r app/build/outputs/apk/debug/app-debug.apk
adb install -r app/build/outputs/apk/androidTest/debug/app-debug-androidTest.apk
adb shell am instrument -w com.sanogueralorenzo.amarchy.test/androidx.test.runner.AndroidJUnitRunner
```

The build downloads checksum-pinned ARM64 packages and Omarchy source, then bundles a gzip environment in the APK. First use extracts it into private storage; allow several GB for preparation and updates. No root, separate Linux installer, runtime download or account setup is required.

Maintainers explicitly refresh package inputs with `python3 runtime/lock.py`, review the lock, and rebuild. Builds never refresh the lock automatically. See [third-party notices](THIRD_PARTY.md) for source pins and licenses.
