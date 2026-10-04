# Android Deck

Build a minimal Steam Deck experience on Android with understandable code and measured improvements in startup, resource use, and responsiveness. Simplify the product and its architecture together.

- Require Android 16+ (`minSdk = 36`), ARM64, and supported Adreno hardware. Validate one real device first. Assess `targetSdk` separately against runtime execution requirements.
- Keep one Steam session mode. The initial scope excludes desktop apps, emulators, external game imports, frame generation, and preview/test update channels.
- Use a small Kotlin Views/XML frontend and a native rendering surface. Steam owns sign-in, the library, downloads, and its interface.
- Organize by feature: setup, runtime, session, display, audio, and input. Keep activities and services thin; extract cohesive responsibilities, not arbitrary file fragments.
- Give session state and process lifetime one owner. Make startup, failure, shutdown, and recovery explicit; release resources and reap session processes reliably.
- Prefer a pinned runtime and matched driver pair for the first device. Use explicit configuration and actionable errors instead of nested routing and silent fallbacks.
- Share code only when existing callers demonstrate the same responsibility. Avoid generic helper collections, speculative interfaces, and configurable frameworks for a single path.
- Reuse established low-level components where appropriate. Understand required compatibility behavior before removing it; preserve applicable licenses and attribution for reused code.
- Remove replaced implementations, dependencies, and configuration. Preserve necessary graphics, audio, input, and process handling even when they cost lines.
- Treat LOC reduction as evidence, not a quota. Do not move complexity into scripts, generated code, or abstractions to make a count smaller.
- Measure release builds on the same device and workload: startup to usable Steam, memory, idle CPU, frame pacing, and input responsiveness. Report improvements only when supported by measurements.
- Verify runtime installation, session startup, stop/relaunch, and failure cleanup with focused checks. Use the real device for graphics and gameplay validation; an emulator covers the frontend and generic Android behavior.
