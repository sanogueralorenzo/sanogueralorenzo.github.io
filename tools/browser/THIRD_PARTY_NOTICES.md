# Third-party notices

Lean derives from Paul Davis's [Crest](https://github.com/pauljoda/Crest),
licensed under the [Mozilla Public License 2.0](LICENSE).
The sidebar's projected reorder layout, pinned slots, floating drag-preview host,
activation handoff and motion roles adapt the matching Crest components.

The GitHub live folder adapts response formats and selectors from
[Zen Browser](https://github.com/zen-browser/desktop/blob/2ad194525da74d7f00609a424d93a3c7db430d21/src/zen/live-folders/providers/GithubLiveFolder.sys.mjs),
also under MPL-2.0.

The bundled [uBlock Origin Lite](https://github.com/uBlockOrigin/uBOL-home)
Safari extension is copyright Raymond Hill and licensed GPL-3.0-or-later.
`Resources/uBlockOriginLite.zip` includes its license, source code and filtering
data. `Resources/uBlockOriginLite.json` records the upstream release and hashes.
Lean adapts runtime detection for WebKit's extension URL scheme, selects Complete
filtering with EasyList Spanish and adds a native startup handshake;
filtering algorithms and rules are unchanged.
The matching upstream build sources are linked from that release's repository
(including its pinned `uBlock` submodule).

The app uses Apple system frameworks, including WebKit, SwiftUI, Translation,
AuthenticationServices, CoreLocation, MediaPlayer, and UserNotifications.
[XcodeGen](https://github.com/yonaskolb/XcodeGen) is an MIT-licensed build tool
and is not shipped inside the app.
