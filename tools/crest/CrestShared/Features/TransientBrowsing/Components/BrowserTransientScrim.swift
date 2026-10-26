import SwiftUI

/// The dimmed ground a transient overlay's card floats on.
///
/// The scrim is also the way out of the card, so it is a button. How much of it
/// shows is the arrangement's business: a floating card leaves generous ground
/// around itself, a handheld card leaves only the strip past its safe-area
/// insets. Either way a tap that lands outside the card is a tap that meant to
/// leave it.
struct BrowserTransientScrim: View {
    let opacity: Double
    let allowsDismissal: Bool
    let dismiss: () -> Void

    var body: some View {
        if allowsDismissal {
            Button(action: dismiss) {
                scrim
            }
            .buttonStyle(.plain)
            .accessibilityHidden(true)
        } else {
            scrim
                .accessibilityHidden(true)
        }
    }

    private var scrim: some View {
        Color.black.opacity(opacity)
            .ignoresSafeArea()
            .contentShape(.rect)
    }
}
