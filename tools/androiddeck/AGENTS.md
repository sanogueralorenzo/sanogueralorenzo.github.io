# Android Deck

Build a minimal Steam Deck experience on Android with clear responsibilities, minimal dependencies, and efficient startup, resource use, and input handling. Deliver working, reliable behavior with the simplest complete implementation. Optimize measured bottlenecks and keep complexity justified by current requirements.

- Investigate [DroidDeck](https://github.com/Droid-Deck/DroidDeck) to understand the runtime, Steam integration, and Android bridges. Compare realistic alternatives relevant to the current task, then choose the simplest reliable approach that meets the requirements. Reuse its code when that comparison supports it; all other guidance still applies.
- Require Android 16+ (`minSdk = 36`), ARM64, and supported Adreno hardware. Validate one real device first. Assess `targetSdk` separately against runtime execution requirements.
- Keep one Steam session mode. The initial scope excludes desktop apps, emulators, external game imports, frame generation, and preview/test update channels.
- Use a small Kotlin Views/XML frontend and a native rendering surface. Steam owns sign-in, the library, downloads, and its interface.
- Organize by feature as responsibilities emerge. Setup, runtime, session, display, audio, and input are possible boundaries, not required scaffolding. Keep activities and services thin; extract cohesive responsibilities without creating unused folders, wrappers, or interfaces.
- Give session state and process lifetime one owner. Make startup, failure, shutdown, and recovery explicit; release resources and reap session processes reliably.
- Prefer a pinned runtime and matched driver pair for the first device. Use explicit configuration and actionable errors instead of nested routing and silent fallbacks.
- Share code only when existing callers demonstrate the same responsibility. Avoid generic helper collections, speculative interfaces, and configurable frameworks for a single path.
- Prefer established low-level components over rebuilding mature engines. Adopt compatibility helpers and workarounds only for demonstrated needs; preserve applicable licenses and attribution for reused code.
- Implement only the current scope and add dependencies or abstractions only for concrete needs. Keep the complete execution path understandable across Kotlin, native code, and runtime scripts.
- Remove replaced implementations, dependencies, and configuration. Preserve necessary graphics, audio, input, and process handling.
- For changes to execution or rendering paths, measure the affected performance metrics in release builds on the same device and workload: startup to usable Steam, memory, idle CPU, frame pacing, or input responsiveness. Report improvements only when supported by measurements.
- Scale validation to the change. Check affected behavior such as runtime installation, session startup, stop/relaunch, and failure cleanup; run broader checks only when the change or evidence warrants them. Use the real device for graphics and gameplay validation; an emulator covers the frontend and generic Android behavior.
