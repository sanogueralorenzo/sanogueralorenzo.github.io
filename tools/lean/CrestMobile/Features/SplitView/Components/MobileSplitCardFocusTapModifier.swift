import SwiftUI

/// Makes a tap on a card that has no web content ask for focus.
///
/// The live-page case gets its focus tap from `MobileBrowserWebView`, which
/// installs a `UITapGestureRecognizer` on the web host with
/// `cancelsTouchesInView = false` — the only arrangement that both hears the tap
/// and still lets the page have it. A placeholder or failure card has no host to
/// install anything on, so it watches for the tap from the window instead,
/// which leaves the card's own controls their taps and clicks.
///
/// A `nil` action leaves the view untouched rather than attaching a gesture that
/// does nothing, so a card that is already the focused one adds no recognizer
/// at all.
struct MobileSplitCardFocusTapModifier: ViewModifier {
    let requestFocus: (() -> Void)?

    func body(content: Content) -> some View {
        if let requestFocus {
            content.modifier(BrowserPlatformObservedTapModifier { requestFocus() })
        } else {
            content
        }
    }
}
