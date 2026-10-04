# Android Deck

Planned Android app that brings the Steam Deck experience to supported Android devices through a Linux runtime, Steam's Deck interface, and Proton for Windows games. Games run locally, with no root required.

## Minimum scope

- A small Android frontend for setup, launching Steam, and stopping a session.
- Install and update the Linux runtime and select compatible GPU drivers automatically.
- Run Valve's Steam client; Steam handles sign-in, the library, and game downloads.
- Connect graphics, audio, controllers, touch input, and the keyboard to Android.
- Handle Android lifecycle events, clean shutdown, and basic diagnostic logs.

Start with one tested ARM64 Adreno device. Game compatibility and performance must be validated on that device. Desktop apps, emulators, external game imports, and frame generation are outside the initial scope.

## Intended setup

1. Install the APK on a supported device.
2. Download the Linux runtime and allow space for Steam, Proton, and games.
3. Disable Android's child-process restriction, with a guided wireless-debugging flow when needed.
4. Launch Steam, sign in, and install a compatible game.

Planning only: no app or build is available yet.
