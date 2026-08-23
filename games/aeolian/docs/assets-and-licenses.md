# Asset, license, and placeholder register

Last reviewed: 2026-08-23 · Owner: production · Policy: register on import

Every non-code asset must list source/creator, source URL or source file, license,
license text/attribution requirement, modification, and shipping status. Generated
assets also record tool/model, date, prompt/source references, and applicable use
terms. “Free” is not a license. Unknown provenance is release-blocking.

## Current register

| Asset | Source/creator | License / attribution | Modification | Status |
| --- | --- | --- | --- | --- |
| `icon.svg` | Probable Godot project-template default; exact creator/source unverified | Unverified; repository MIT license does not establish this asset's provenance | None observed | Development placeholder; replace before branding lock |

There are no other art, audio, font, model, texture, shader, or third-party plugin
assets in the project as of the review date.

## Placeholder replacement list

| Placeholder | Intended replacement or retention decision | Due gate | Owner |
| --- | --- | --- | --- |
| Default Godot `icon.svg` and imported derivative | Original AEOLIAN application icon with source file and rights record | Phase 9 | Art/production |
| Primitive/debug geometry introduced during movement work | Replace with intentional windboard/rider/course art, or document an intentional stylized retention | Phase 3 for slice area; Phase 9 globally | Art |
| Synthesized/debug tones | Replace with licensed/original surface, wind, UI, crash, and music assets | Phase 3 representative; Phase 9 final | Audio |
| System/default fonts if used | Select a redistributable font, include license and fallbacks | Phase 8 | UI/production |
| Debug text/icons | Remove from release or move behind development feature guard | Every phase; final Phase 9 audit | Engineering/UI |

## Import checklist

- Store editable source separately when it belongs in the repository; never lose
  the source that produced a shipping derivative.
- Use predictable lowercase paths and identify compression, color-space, looping,
  LOD, collision, and platform overrides deliberately.
- Add the register row in the same change as the asset.
- Copy required license text into a future `licenses/` directory and credits plan.
- Record whether marketplace/AI/source terms permit commercial game distribution.
- Remove rejected assets and their imports; do not leave an untracked content dump.
- Before every content gate, compare tracked assets against this register and the
  placeholder list.
