# Link opening

The core decides where a followed link or an opened window goes, on both
engines and every platform: the `LinkNavigation` query and the engines'
`LinkActivation` question for a followed link, and `PageOffered` for a window
an engine made. Link selection follows fixed gesture rules.

| Gesture | Result |
| --- | --- |
| Command-click or middle-click link | Background tab |
| Same gesture with Shift | Selected tab |
| Option-click link | Selected tab |
| Scripted new window with Command-click or middle-click | Background tab, selected when Shift is held |
| Direct link or scripted same-page navigation | Current page |
| Plain click leaving a pinned or saved tab's site | Selected tab, preserving the saved page |
| Unmodified `target=_blank`, form target, or `window.open` | Selected tab beside the opener |

These rules apply on macOS, iPhone and iPad. A script that does not preserve a
link or new-window gesture cannot be classified from the appearance of its
card. Crest does not rewrite sites or infer missing input intent.

Moving tabs to another Space, through a menu or drag and drop, selects that
Space and the moved tab. Moving a batch selects its first tab in sidebar order.

A page another page opens stays on its opener's engine, whatever the site's
engine choice. The engine loads the page it made for a new window, so opener
identity, writable blank windows, request bodies and the source profile
survive.

## Loading and residency

Intentionally opened background links start immediately. Selecting the new tab
reuses that page. Memory pressure never unloads a page that has not shown a
document yet, on any platform; afterwards it treats the page like any other tab
page off screen.

Entering a Space is a separate action. An existing unloaded tab remains unloaded
on mere Space entry, and the Mac shows Start Page until explicit tab selection.
Resident and in-flight pages retain their existing behavior.

There is no deferred-loading preference. Public WebKit requires an accepted native
window's view to be returned synchronously, and its opener may immediately write
to or message it. Cancelling that navigation and replaying a URL later would lose
those semantics and can discard request data. A switch that delays ordinary anchors
but still runs scripted windows would give the two paths different loading behavior.
Supporting a broader deferred mode would require a separate, explicit capability
contract before exposing that choice.

## Public API references

- [WKNavigationAction](https://developer.apple.com/documentation/webkit/wknavigationaction)
- [Creating a new WebKit view](https://developer.apple.com/documentation/webkit/wkuidelegate/webview(_:createwebviewwith:for:windowfeatures:))
- [Safari tab settings](https://support.apple.com/guide/safari/tabs-ibrw1045/mac)

The core's link policy tests cover these decisions. Site-specific event
handling and physical keyboard or pointer behavior also need validation in the
running browser.
