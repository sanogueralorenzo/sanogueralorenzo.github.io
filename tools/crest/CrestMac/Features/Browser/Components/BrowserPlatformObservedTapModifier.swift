import SwiftUI

/// Tells `action` about a click inside the content alongside whatever the
/// click reaches.
struct BrowserPlatformObservedTapModifier: ViewModifier {
    let action: @MainActor () -> Void

    func body(content: Content) -> some View {
        content.simultaneousGesture(TapGesture().onEnded { action() })
    }
}
