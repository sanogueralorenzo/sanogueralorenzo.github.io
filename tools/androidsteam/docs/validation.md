# Device validation

Samsung S24 SM-S921U1, Android 16/API 36, Snapdragon 8 Gen 3/Adreno 750. Results cover this device and the configurations below. Account data, five installed games, saves and existing control selections are preserved; APK replacement uses `adb install -r`.

## Current runtime and setup

The published [Arch ARM snapshot](https://github.com/sanogueralorenzo/sanogueralorenzo.github.io/releases/tag/androidsteam-runtime-20261005-1) uses 242 reviewed packages, GNU libc 2.43, Zink-only Mesa 26.2.3, Gamescope 3.16.31, XWayland 24.1.13 and SDL 3.4.16. Required graphics, audio, fonts, encodings, certificates and dynamically loaded resources remain. Steam, games, saves and ARM64 Proton live in the separate home and retain Valve's update mechanisms.

Two independent rebuilds match. The base archive shrank from 162610928 to 99009976 bytes; Android runtime usage fell from 817661 to 522273 KiB. Fresh preparation measured 72672 versus 54473 ms, one sample each excluding network. These are size savings and an observed preparation reduction, not a repeatability or graphics-speed claim. [Runtime minimization](runtime-minimization.md) records each validated batch, total downloads, dependencies and measurement limits; [runtime build](runtime-build.md) documents locks and safe updates.

Replacement, cancellation, truncated download and interrupted-swap recovery passed (109.784 s), preserving a separate-home sentinel. Eleven graphics/dependency/audio/lifecycle checks passed (30.289 s). Native Setup installed the published marker and reached Ready. Published reuse/cancellation/foreground-service checks passed (four tests, 3.149 s); isolated fresh verified downloads, cancel/retry and home preservation passed (93.693 s). Download fixtures must foreground the native activity; an earlier background fixture timed out.

## Steam and native launcher

Steam's own QR login, delivered online-account observation, live available licenses and restart persistence passed. Native authentication experiments remain deferred outside this source tree. No tokens or credentials are used by native sign-in UI.

Native Library/Search/Downloads/details/settings use live local-client licenses, an account-scoped offline snapshot, product metadata and installed manifests. Files/artwork never prove ownership. On the S24, 47 available licenses joined metadata and visibility rules to produce 45 visible games; free/shared licenses can differ from purchases or Steam's displayed count. Refresh timestamps distinguish live and cached results.

Play starts or reuses one session; changed launch settings restart an idle client, and game exit returns to native details. Steam manages installation, cloud prompts and updates. Real install/download progress was checked through Steam and native manifest counters; the temporary test game was removed through Steam. Portrait/landscape native search works with Samsung's IME and restores layout after dismissal.

Debug/test/minified release assembly, 27 unit tests and lint pass. Device checks cover live library/offline browsing, profile projection and idempotence, idle-client profile restart, dependency loading, keyboard/touch, background/resume, audio-failure cleanup and clean shutdown. A replacement Android session screen resumes rendering while retaining the same client bridge. Notification Stop uses Valve’s graceful shutdown before bounded forced cleanup. After Brotato Quit, one stop reaped all Linux in 10.512 s and removed the crash/PID markers; CEF retained broken Singleton symlinks. Startup clears only these stopped-client transient markers after reaping the previous owner.

Play waits for client-mode readiness and the existing signed-in-user observer, then sends Steam's game/install URI through the already-connected client's `SteamClient.URL.ExecuteSteamURL` binding, which Steam's bundled UI also uses. Steam retains its launch settings and prompts. The owner retains Play until a tracked game event, with bounded requests and retries within five minutes. The separate command relay is removed; no new authentication flow is implemented.

The [pinned PRoot implementation](https://github.com/termux/proot/blob/4dba3afbf3a63af89b4d9c1a59bf2bda10f4d10f/src/extension/sysvipc/sysvipc.c#L152) allocates a namespace per invocation and shares it only with descendants. Shutdown therefore invokes Valve's executable inside the existing session. The game URI travels through the connected client; forwarding alone never proves gameplay. Reproduced relaunch failures and the resulting replacement policy are recorded below.

## Game configurations and demonstrated behavior

All three Windows games use **Android Steam Proton (ARM64)**, which calls Steam-managed **Proton Experimental (ARM64)** directly. The checked depot was app 4427310/build 25646942, about 497871024 download bytes and 2080051656 installed bytes; Valve may update it. Native overlay injection is excluded from Wine after a reproduced IPC relaunch crash; the required Android memory/graphics/input adapters are versioned separately.

| Game | Launch configuration | Verified behavior |
| --- | --- | --- |
| Superflight (732430) | `-force-d3d11 -screen-width 1280 -screen-height 720 -screen-fullscreen 1` | Flight, steering, collision/retry, Home/resume, Quit and repeated warm launch; saved high score retained. |
| Brotato (1942280) | `--video-driver GLES2` | Saved-run resume, movement/firing/collection, completed waves/shop, Home/resume and Quit. GLES3 previously stalled at splash. |
| SNØ (2943150) | No extra arguments; WASD, optional P/R keys | Downhill steering, Space, collision/results/retry, photo/pause, Home/resume and Quit to native details. |

Superflight also starts/retries with virtual Xbox A and visibly banks with its analog stick in the minified version-10 release candidate. It required Valve's existing `PROTON_SPOOF_STEAMINPUT_VIDPID=1` for its Unity/HID path; the launch adapter defaults this option while honoring an explicit override. The same Android focus fix without spoofing did not make A work. Superflight's original Arrow selection, Brotato's Direct touch and SNØ's WASD/optional keys are restored after checks.

## Xbox controls and direct touch

New games default to Xbox; saved Direct touch/Arrow/WASD choices remain. Native settings and the in-game selector expose all four layouts. Floating sticks appear on touch and hide on release; buttons are highly translucent with pressed feedback. Each pointer belongs to a control or the game surface until release, allowing direct touch outside controls while a controller input is held.

Linux checks validate evdev/uinput identity, capabilities, buttons/axes, neutral release, late-open state, Wine-only udev discovery and hot removal. The v9 raw-close/eventfd-reuse regression fails because anonymous eventfds share inode identity and an unrelated wakeup write is intercepted. V10 uses a unique pipe sentinel; its preload is 291784 bytes and requires only libc/libm. This is a demonstrated descriptor fix, without an asserted causal link to every Steam crash. Seven affected S24 checks pass (136.926 s), including the failing regression, rendered Windows x64 XInput A/analog/neutral and both simultaneous touch/controller pointer orders. Steam reports one Xbox 360 controller. Physical hardware, vibration and broader compatibility remain unverified; unsupported force feedback is not advertised.

## Compact Xbox redesign

The follow-up `androidsteam-20261005-2` APK is **1054121 bytes**, SHA-256 **`efb00c7bd977ab932d3a0b2209469a528cf545aebe8fbf4ca479607920fb195a`**. V3 signature, installed hash, absence of DEBUGGABLE/debug probes and build/lint pass. Only the onscreen Xbox layout/drawing/hit areas change; the Arch base, native controller bridge and Steam replacement policy are unchanged.

Our edge layout replaces the inherited automatic arrangement. Face buttons are 36 dp across and floating sticks 60 dp across at full scale; button hit targets are at least 48 dp across at full scale. Idle fills/outlines/labels use approximately 3%/12%/21% opacity, with brighter pressed feedback. D-pad arrows have no persistent circles. Both sticks appear on touch and disappear on release. The remaining adapted input handling retains DroidDeck attribution.

Four focused S24 checks pass (87.129 s): Linux Xbox/Steam Input identity and release, rendered Windows x64 XInput A/analog/neutral, and simultaneous direct touch/controller input in both pointer orders. The signed release reaches Superflight's actual menu in 62.46–64.70 s from native Play; original 22391 high score/8548 combo remain. A tap outside A's visible circle but inside its hit target starts flight; analog steering banks the character. Idle/held/pressed/released states are visually checked, pause/Quit returns to native details, and the original Arrow selection is restored. Notification Stop reaps all Linux processes in 10.263 s. No new cross-game/runtime tuning or startup/FPS improvement is claimed.

A 20.06-second Superflight pause-menu sample with idle Xbox controls records 872 Android presentations, median/p95 spacing 16.669/49.989 ms. This is presentation spacing, not engine FPS or input-to-photon latency; scene/thermal differences prevent a matched performance claim. The previous full release's cross-game/relaunch acceptance remains below.

## Fixed release acceptance and relaunch cost

Final signed minified APK: **1058217 bytes**, SHA-256 **`9a934e5df2ec4e94b3b5c8b59192c96e8280ae0ef2b5ad0760b00d566a578c34`**. V3 signature and installed hash verified; DEBUGGABLE and debug probes are absent, packaged launch script matches source. Runtime marker `arch-arm64-20261005-1`, adapters `arch-android-adapters-10`, Steam `steamdeck_stable`, Proton app 4427310/build 25646942. Runtime, controller and replacement configuration stayed fixed throughout acceptance. [Release checks](release-checks.md) give the repeatable procedure.

Published [release androidsteam-20261005-1](https://github.com/sanogueralorenzo/sanogueralorenzo.github.io/releases/tag/androidsteam-20261005-1) targets source commit `428519bd6b8b3b57dbdcebbc28987b41bfd6136e` on main. An independent download matches the tested APK hash/size and its checksum asset; the downloaded APK passes v3 signature verification. The remote tag resolves to the recorded source commit.

Build, 27 unit tests and lint pass. All seven affected device checks pass (136.926 s); final diagnostic/UI lifecycle recheck passes (three tests, 58.678 s). Injected audio failure releases resources, removes the spinner, keeps Library visible and shows recovery instructions. The owner emits one sanitized audio-failure record (`cause=audio phase=display-ready appId=0 steamExit=null displayExit=null`); intentional shutdown/replacement is excluded. No raw account/Steam logs or crash heaps are retained.

A surface frame or tracked process does not pass gameplay acceptance. Timings below bound the first observed usable menu after native Play, using screenshots sampled approximately every 1–5 seconds plus capture/OCR overhead. Background/resume and Quit are checked in actual gameplay. The same signed APK passed both cold starts, two post-Quit launches and both cross-game switches.

| Fixed APK flow | Usable-menu bounds | Result |
| --- | --- | --- |
| Superflight cold Play | 66.64–69.01 s | Usable menu, Xbox A/analog flight, held/released stick, pause/Home/resume; original Arrow and saved 22391 high score/8548 combo retained. |
| Superflight Play after Quit, twice | 121.56–124.11 / 94.72–97.11 s | Both new clients reach actual menus; keyboard flight/pause/Quit and Arrow/scores persist. First Steam 26218 → 28926/game 30043. |
| Superflight → Brotato | 203.68–209.71 s | Steam 30729 → 32739/game 1409; preserved Wave 2 shop (49 currency), direct-touch GO → Wave 3, keyboard movement, pause/Home/resume, touch Return to Main Menu and Quit to native details. |
| Brotato → SNØ | 94.05–101.79 s | Steam 32739 → 5368/game 6562; actual downhill movement/Space, photo mode, touch P/R, collision/retry and Home/resume; Quit returns to native details; original WASD/extra keys and 249369 high score/233540 combo retained. |
| Second cold Play after app/session restart | 82.90–85.71 s | Native Setup remains Ready, Samsung IME search/filter/dismissal passes; retained sign-in launches Superflight (Android PID 9543/Steam 11152/game 11997). Live refresh passes (45 games); a further launch verifies original online scores again. |

One cold Superflight menu showed 164 high score/combo with “No online rank”. Another launch of the unchanged APK reached its menu in 90.62–93.65 s (Steam 11152 → 13774/game 14553) and restored the original 22391/8548 and online ranks without modifying data/settings. This verifies the original stats remain; the cause of their temporary unavailability is unestablished. No session-owner failure was recorded. Online-stat availability is separate from launch/menu acceptance and is not guaranteed by these checks.

After the final game Quit, live library refresh again returns 45 games and Profile → Open Steam remains usable without another sign-in. Notification Stop reaps all Linux processes in 10.584 and 5.043 seconds across the final checks; only the native Android app remains. Neither final release Android process emits a session-owner failure.

### Reproduced failures supporting replacement

| Rejected candidate / reproduced flow | Sanitized observation | Recovery / decision |
| --- | --- | --- |
| V10 direct client reuse (`855e8d32…`), Superflight → Brotato | Steam `DelayLaunch`, then exit 139 before a Brotato game process/menu | All Linux reaped; clean-client Brotato menu 201.79–208.05 s; preserved Wave 2 shop/gameplay/resume/Quit passed. Reuse rejected. |
| Different-ID-only replacement (`2e204748…d4b60`), Superflight → Superflight | Steam `Launching executable`, then exit 139; no usable menu | Cleanup/error shown. Same-game reuse rejected. |

No upstream root cause is claimed. Native Play now replaces an idle client that has played any game; Steam stays available for library/management between games. The preceding matching-policy APK (`66323536…7680`) passes Superflight cold 59.60–61.92 s, two post-Quit launches 90.65–93.50 / 113.96–116.33 s and automatic Brotato switch 196.44–202.52 s. Prior successful reused-client samples were 23.72–25.85 / 33.01–35.99 s but that policy also reproduced exit-139 failures. Replacement therefore adds client startup cost, and these variable samples do not show a speed improvement. Final fixed-APK measurements above are the release acceptance evidence.

## Audio and measurements

PulseAudio supplies fixed 48 kHz stereo PCM16 to Android AudioTrack. Real game PCM reaches Android, gain mutes/restores on background/resume and stop cleans up. The FIFO capacity is 4096 bytes (21.3 ms), Android playback limit 960 frames (20 ms); game-side reported queues are approximately 10–30 ms. Queue bounds are not acoustic latency. Media volume remained zero, so speaker audibility is unverified.

Earlier native-only release browsing measured 88.9 MiB PSS, 0.8% idle CPU and a 120 ms median first draw across three cold starts. Eight cached-library swipes produced 220 frames with zero Android-reported janky frames. Steam was stopped; asynchronous artwork completion is excluded from first draw.

Earlier same-device Superflight cold native Play reached its usable menu between 75.8 and 89.9 s, warm Play between 15.2 and 36.0 s. Brotato's usable menu was observed between 105 and 199 s. These are coarse screenshot bounds, not exact startup timings. Steam updates can add startup work. Generated scenes and thermal variation prevented credible gameplay speed comparisons; Android presentations are not engine FPS. An earlier Xbox candidate animated menu used 2311.0 MiB aggregate PSS and 384.4% CPU (three samples), with 678 Android presentations over 20.14 s, median/p95 spacing 33.33/50 ms and battery 40.1°C. Different generated scenes/thermal states prevent attributing differences to controls or launch code; no gameplay speedup is claimed.

## DroidDeck comparison

[DroidDeck source 05608ac4](https://github.com/Droid-Deck/DroidDeck/tree/05608ac4d4da33cfebcc0d6783064ec04ac75aee) was compared with the installed debug 0.3.0 APK (SHA-256 `8c8f824ed149538b3ae8ecd31464a6a09cd5d85336c4c9fc0c863e9b6144d2f9`). Proton/pad scripts match. Its APK forces fullscreen while source defaults off to avoid resolution flicker; both set CEF GPU/X11/ANGLE/Vulkan flags. App data was not exported.

The virtual controls/evdev foundation is adapted with GPL attribution; unused logging, rumble transport and path adapters were removed. Game/install requests use the existing local client binding; shutdown uses a small watcher inside the session. A matched pair of minified APKs differed only in five browser flags (`-no-cef-sandbox -cef-force-gpu -cef-ozone-platform=x11 -cef-use-gl=angle -cef-use-angle=vulkan`). Both passed live-license refresh. Same-device 20-second left/right navigation measurements:

| Metric | Steam defaults | CEF candidate |
| --- | ---: | ---: |
| Android presentations | 1172 | 1105 |
| Median / p95 frame gap, ms | 16.664 / 33.331 | 16.664 / 33.455 |
| Aggregate UID PSS, MiB | 1573.2 | 1497.2 |
| CPU median, percent of one core | 237.0 | 256.0 |
| Battery temperature, °C | 38.7 | 39.4 |

Each workload sent 31 navigation requests; idle CPU used three 5-second samples after discarding the first. Resource samples still included Steam/Proton initialization, and temperature/process-count differences limit conclusions. First surface presentation was 24.940 versus 29.203 s; this includes bootstrap work and is not usable-Steam timing. No clear improvement justifies the extra flags, so Steam defaults remain. ADB command durations do not measure input-to-photon latency. FIFO presentation is already shared; no evidence justified Choreographer/threading, realtime scheduling, GPU clock pinning, frame generation or experimental SurfaceControl paths.
