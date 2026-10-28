import SwiftUI

extension EngineMark {
    /// The drawing the core's mark names. This is the one place a mark becomes
    /// artwork; each fits the frame it is given and draws no ground of its own.
    @MainActor @ViewBuilder var artwork: some View {
        switch self {
        case .stackedTile: EngineStackedTileMark()
        case .globe:
            Image(systemName: "globe")
                .resizable()
                .scaledToFit()
                .foregroundStyle(.blue)
        }
    }
}
