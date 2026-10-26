import SwiftUI

/// Stores the user's position independently of a ScrollView's mounted lifetime.
@MainActor
final class BrowserNativeScrollState {
    var offset: CGFloat = 0
    var listRow: Int?
    var listRowOffset: CGFloat = 0
}

private struct BrowserNativeScrollRestoration: ViewModifier {
    let state: BrowserNativeScrollState
    private let restoredOffset: CGFloat
    @State private var position: ScrollPosition

    init(state: BrowserNativeScrollState) {
        self.state = state
        restoredOffset = state.offset
        _position = State(initialValue: ScrollPosition(y: state.offset))
    }

    func body(content: Content) -> some View {
        content
            .scrollPosition($position)
            .onAppear {
                withTransaction(Transaction(animation: nil)) { position.scrollTo(y: restoredOffset) }
            }
            .onScrollPhaseChange { _, phase, context in
                // Recorded when a scroll comes to rest rather than on every
                // frame: following the offset would update the view graph
                // each frame the content moves.
                guard phase == .idle else { return }
                state.offset = max(0, context.geometry.contentOffset.y + context.geometry.contentInsets.top)
            }
    }
}

extension View {
    func browserNativeScrollState(_ state: BrowserNativeScrollState) -> some View {
        modifier(BrowserNativeScrollRestoration(state: state))
            .id(ObjectIdentifier(state))
    }
}
