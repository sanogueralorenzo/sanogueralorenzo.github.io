import SwiftUI

struct BrowserPlatformSitePermissionMenuModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .menuStyle(.borderlessButton)
            .fixedSize()
    }
}
