import SwiftUI

/// Mobile floats the find bar as a Liquid Glass capsule, with plain controls
/// inside it.
struct BrowserPlatformFindBarStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .buttonStyle(.plain)
            .glassEffect(.regular, in: .capsule)
    }
}
