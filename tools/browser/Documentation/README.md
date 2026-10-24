# Crest documentation

The product site and [Crest Help](https://crestbrowser.com/guides/) explain how
to use the browser. This directory describes the source, product behavior, and
build and release requirements for contributors.

Crest ships Chromium and WebKit together on Mac, backed by the shared native
core. iPhone and iPad keep WebKit. Start with the [engine and migration guide](../HelpCenter/docs/browsing/engines.md)
for user-visible behavior, or the architecture references below for ownership
and implementation details.

## Start here

- [Architecture](ARCHITECTURE.md) covers Space isolation, persistence,
  credentials, synchronization, and the engine boundary.
- [Roadmap](ROADMAP.md) lists public release outcomes and platform gates.
- [Repository guardrails](RepositoryGuardrails.md) describes source layout,
  validation, dependencies, and public-source checks.
- [Distribution](Distribution.md) covers release channels, signing,
  notarization, appcasts, and release verification.

## Browser behavior

- [Content blocking](Architecture/ContentBlocking.md)
- [Desktop Picture in Picture](Architecture/DesktopPictureInPicture.md)
- [Link opening](LinkOpeningPolicy.md)
- [Native tab content](NativeTabs.md)
- [Core architecture](Architecture/CoreArchitecture.md)
- [Portable control plane](Architecture/ControlPlane.md)
- [Engine abstraction](Architecture/EngineAbstractionCompletion.md)
- [Chromium engine](../CrestEngines/Chromium/README.md)

## Project participation

See [SUPPORT.md](../SUPPORT.md) for community and reporting routes,
[CONTRIBUTING.md](../CONTRIBUTING.md) for local development,
[GOVERNANCE.md](../GOVERNANCE.md) for ownership and decision making, and the
[`crest-contribution` skill](../.agents/skills/crest-contribution/SKILL.md)
for the rules every AI-assisted change must follow.
