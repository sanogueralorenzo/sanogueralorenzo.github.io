import SwiftUI

struct BrowserCommandPaletteScrim: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.browserCommandPaletteTransitionPhase) private var transitionPhase

    let dismiss: () -> Void

    var body: some View {
        Button(action: dismiss) {
            Color.black.opacity(
                BrowserCommandPaletteMetrics.scrimOpacity.scrimOpacity(reduceTransparency: reduceTransparency)
            )
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .ignoresSafeArea(.container, edges: .all)
        .opacity(transitionPhase.isIdentity ? 1 : 0)
        .accessibilityHidden(true)
    }
}
