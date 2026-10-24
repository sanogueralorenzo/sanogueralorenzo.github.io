import SwiftUI

extension View {
    func browserCredentialDetailSizing() -> some View {
        modifier(BrowserPlatformCredentialDetailSizingModifier())
    }
}
