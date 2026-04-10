# super_overlay

Flutter app scaffold for the Super Overlay project.

## Default Entry Screen

The app now opens on `lib/features/home/home_screen.dart` by default.
From there, you can open the `Overlay` access point (ported UI) or the login architecture example.

## Overlay Android Bridge

`lib/features/overlay` now uses a Pigeon host API to call Android overlay code.
The bridge implementation lives under `android/app/src/main/kotlin/com/example/super_overlay`.

## Login Example

`lib/features/login` shows a complete example using:

- `dio` for HTTP client setup
- `retrofit` for typed API contracts
- `get_it` + `injectable` as the injector setup
- `freezed` for immutable state and models

The example uses a placeholder API base URL (`https://api.placeholder.super-overlay.dev`)
and a placeholder login endpoint (`POST /auth/login`).

## Useful Commands

```bash
flutter pub get
dart run pigeon --input pigeons/overlay_api.dart
dart run build_runner build --delete-conflicting-outputs
flutter analyze
flutter test
```
