import SwiftUI

/// Forwards to ``CrestButtonStyle`` role `.secondary`. New code writes
/// `.buttonStyle(.crestSecondary)`.
struct BrowserOnboardingSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        CrestButtonStyle(role: .secondary)
            .makeBody(configuration: configuration)
    }
}
