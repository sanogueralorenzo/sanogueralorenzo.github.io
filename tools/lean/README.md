# Lean Next

A WebKit browser based directly on [the Crest fork](https://github.com/sanogueralorenzo/Crest).
It retains Crest’s sidebar, Spaces, folders, splits, media, browser data,
permissions, sync, agents, and bundled uBlock Origin Lite.

## Build

Requires Apple silicon, macOS 26.1+, Xcode, XcodeGen, and the .NET SDK pinned in
`CrestCore/global.json`. Native sources keep Crest’s existing module names.

```sh
Scripts/run-local.sh --build-only
```

Omit `--build-only` to launch an isolated review profile. The local build has its
own bundle identifier and keeps its data under `LeanNext`, separately from Crest.
Never run fixtures against a personal profile.

Generate the Xcode project with `xcodegen generate`; the desktop scheme is
`Crest`, producing `LeanNext.app`. Mac tests use the `CrestTests` target.
The existing iPhone/iPad sources and `CrestMobile` scheme are retained.

Source is [MPL-2.0](LICENSE). See [third-party notices](THIRD_PARTY_NOTICES.md).
