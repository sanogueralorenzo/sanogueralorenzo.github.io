# App

Flutter client scaffold for Codex tooling.

## Quickstart

```shell
flutter pub get
dart run build_runner build
flutter analyze
flutter test
flutter run
```

## Architecture

- `lib/src/mavericks`: Mavericks-style state, view model, and widgets.
- `lib/src/di`: `get_it` + `injectable` dependency wiring.
- `lib/src/navigation`: typed `go_router` routes.
- `lib/src/network`: Dio client setup, API selection, proxy support, and error handling.
- `lib/src/theme`: shared Material theme.
- `lib/src/features/example`: neutral example feature with UI, Mavericks view model, repository, Retrofit API, and generated models.

Generated files are committed so the project builds immediately after dependency restore.
