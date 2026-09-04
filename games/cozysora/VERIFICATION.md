# Cozy Sora runtime verification

Verified on 4 September 2026 with Godot 4.7.2, Forward+, Metal, Apple M3 Max, at 1280 × 720.

Rendered runtime inspection covered the normal cat view and ten scenic viewpoints: coast, paddy, farm, rail, village, alley, vending, viaduct, shrine, and top. Visual review covered camera visibility, vegetation density, materials, buildings, props, flowers, bridge structure, signs, water, and rice fields. See [DESIGN.md](DESIGN.md) for the procedural systems.

Native play exercised the title card, character selection, Escape/menu transitions, cat movement along the approach and coastal road, gull gliding, ascent and descent, landing, Tab switching, and returning safely to land after switching over the sea. Jump input was exercised with a stable landing; the inspection tool did not capture its apex. Captured-mouse relative look could not be exercised reliably through the UI automation interface, so its event handling and camera math were inspected in code instead. This is the remaining manual verification gap.

The normal native play session held 120 FPS after loading, with approximately 0.3–0.8 ms physics processing. Screenshot generation and concurrent browser rendering reduce observed capture-run FPS, so those numbers are not representative gameplay benchmarks. A complete fresh terrain/vegetation generation took approximately 21 seconds; warm launches reused the generated cache. The final capture run and native play produced no script errors or crashes.

No tests were created. Verification consisted of rendered runtime inspection, native interaction, source review, and engine log inspection. No external game assets or source code are bundled.

## Branding verification

The title screen and reopened character menu display only “Cozy Sora” as the game name. The native debug window shows “Cozy Sora (DEBUG)”; the suffix is added by the engine. Project metadata and all documentation use “Cozy Sora.” There is no separate export preset with a title override.

The branding update was launched in Godot 4.7.2. Gameplay entry, character switching, ascent input, and Escape/menu reopening ran without script errors. Rendering returned to approximately 120 FPS after loading. Gameplay algorithms, world parameters, shaders, controls, and rendering settings were unchanged.

Case-insensitive content and filename searches covered the project, including hidden files, and the repository's current distributable files. The audit also normalized spacing, punctuation, Unicode, escaped characters, and URL encoding to check title and domain variants. No former branding, external web URLs, or obsolete attribution remains in the project. Git history is retained unchanged.
