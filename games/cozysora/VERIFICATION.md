# Runtime verification

Verified on 4 September 2026 with Godot 4.7.2, Forward+, Metal, Apple M3 Max, at 1280 × 720.

The deployed reference was run in a browser and its application bundles were inspected. Repeated Godot capture passes used the reference's camera coordinates and field of view for the normal cat view and all ten named viewpoints: coast, paddy, farm, rail, village, alley, vending, viaduct, shrine, and top. Two independent critics compared rendered views against the running reference and reviewed the relevant source algorithms.

The review cycle corrected the initial camera obstruction, foliage placement and card orientation, material tint/color management, village architecture and props, farm timber and roof detail, shrine composition and flower proportions, bridge structure, coastal signs, ocean glints, and the rice field's distant canopy and roadside lamp. Both independent critics passed the finished recreation after the ninth full capture pass. The implementation notes in REFERENCE.md describe the remaining engine-specific rendering choices.

Native play exercised the title card, character selection, Escape/menu transitions, cat movement along the approach and coastal road, gull gliding, ascent and descent, landing, Tab switching, and returning safely to land after switching over the sea. Jump input was exercised with a stable landing; the inspection tool did not capture its apex. Captured-mouse relative look could not be exercised reliably through the UI automation interface, so its event handling and camera math were inspected in code instead. This is the remaining manual verification gap.

The normal native play session held 120 FPS after loading, with approximately 0.3–0.8 ms physics processing. Screenshot generation and concurrent browser rendering reduce observed capture-run FPS, so those numbers are not representative gameplay benchmarks. A complete fresh terrain/vegetation generation took approximately 21 seconds; warm launches reused the generated cache. The final capture run and native play produced no script errors or crashes.

No tests were created. Verification consisted of rendered runtime inspection, native interaction, source review, and engine log inspection. No external visual assets, recorded audio, or reference JavaScript are included in the project.
