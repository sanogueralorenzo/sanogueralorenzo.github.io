import SwiftUI

/// Forwards to ``CrestButtonStyle`` role `.primary`. New code writes
/// `.buttonStyle(.crestPrimary)`; this name survives only so the wizard's
/// existing call sites keep compiling.
struct BrowserOnboardingPrimaryButtonStyle: ButtonStyle {
    var tint: Color = CrestBrandPalette.butter

    func makeBody(configuration: Configuration) -> some View {
        CrestButtonStyle(role: .primary, tint: tint)
            .makeBody(configuration: configuration)
    }
}
