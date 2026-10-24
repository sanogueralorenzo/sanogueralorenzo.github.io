import SwiftUI

/// Touch sizes the credential detail by detent rather than by frame: the sheet opens
/// at half height, which is enough for the account row and the reveal button, and
/// stretches to full height for the longer scopes.
struct BrowserPlatformCredentialDetailSizingModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.presentationDetents([.medium, .large])
    }
}
