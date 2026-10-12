# Amarchy

An Android host being built for the most complete practical upstream ARM64 Omarchy desktop. Android 16+ and ARM64 are the initial baseline. One action prepares the bundled environment and opens Hyprland with Omarchy's own shell, menus, wallpaper, themes, Bash defaults and compatible applications. Mesa supplies software rendering without root or an Adreno requirement.

Choose **Get started** once. **Apps** and **Omarchy** open upstream's menus. **Keyboard** opens or hides Android's keyboard; the desktop resizes above it. **Keys** provides shortcuts and Android clipboard paste. Touch clicks/drags, two-finger movement scrolls, and a keyboard/mouse can operate the desktop. **Home** returns to the app's start screen; **Close desktop** stops the session. The separate home preserves projects and settings across app/runtime updates. Background-session stability, audio, broader app acceptance and release verification are still in development.

## Build

Use JDK 17 or 21, Android SDK 36, NDK `29.0.14206865`, CMake `3.22.1`, Python 3.11+, and macOS Command Line Tools or Linux build tools with Expat and a C++23 host compiler. Set `ANDROID_HOME` or `sdk.dir` in `local.properties`.

```sh
./gradlew :app:assembleDebug :app:assembleDebugAndroidTest :app:lintDebug
adb install -r app/build/outputs/apk/debug/app-debug.apk
adb install -r app/build/outputs/apk/androidTest/debug/app-debug-androidTest.apk
adb shell am instrument -w com.sanogueralorenzo.amarchy.test/androidx.test.runner.AndroidJUnitRunner
```

The build downloads checksum-pinned ARM64 packages and Omarchy source, then bundles a gzip environment in the APK. Allow about 12 GB for the app and installed workspace; runtime replacement needs another 8 GB free. No root, separate Linux installer, runtime download or account setup is required. Android owns locking, networking and hardware controls; incompatible Linux system integrations are disabled.

Maintainers refresh package inputs with `python3 runtime/lock.py SOURCE_ARCHIVE DATABASE_DIRECTORY`, using the reviewed Omarchy source and the core, extra, stable and edge repository databases. Review the generated locks before rebuilding; builds never refresh them automatically. See [third-party notices](THIRD_PARTY.md) for source pins and licenses.
