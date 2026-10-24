import SwiftUI

struct BrowserPlatformCredentialDetailSizingModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.frame(
            minWidth: 380,
            idealWidth: 440,
            minHeight: 330,
            idealHeight: 390
        )
    }
}
