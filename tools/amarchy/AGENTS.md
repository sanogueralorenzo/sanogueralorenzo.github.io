# Amarchy

Follow the repository's top-level `AGENTS.md`.

- Build a polished Android home for an Android-adapted ARM64 Omarchy desktop. One primary action should prepare the environment and enter it; subsequent opens should reuse the installation and running session.
- Keep Android 16+ and ARM64 as the initial baseline. Use the Android emulator for frontend, Linux execution, installation, recovery, and display experiments. Do not equate an emulator screenshot or Linux process with a working Omarchy desktop.
- Keep entry points thin and organize cohesive responsibilities by feature. Reuse proven Android Steam infrastructure without importing its Steam, Proton, authentication, or game-control features. Avoid speculative frameworks and compatibility paths.
- Give installation and desktop processes explicit ownership, cancellation, failure recovery, and reliable cleanup. Preserve the user's home across runtime replacement.
- Pin and verify runtime inputs; retain source provenance, licenses, and attribution. Never label setup complete before the actual desktop can start.
- Read `PLAN.md` during goal work and update its compact resume state after meaningful progress. Preserve the objective and completion criteria unless the user changes scope.
- Verify real rendered desktop apps, input, background/resume, stop/relaunch, and installation recovery before claiming completion. Run focused build/lint and relevant device checks, then commit and push to `main`.
