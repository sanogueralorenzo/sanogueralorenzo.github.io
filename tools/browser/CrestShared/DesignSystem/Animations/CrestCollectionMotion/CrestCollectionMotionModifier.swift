import SwiftUI

/// Animates identity-driven collection changes while honoring Reduce Motion.
struct CrestCollectionMotionModifier<ID: Hashable>: ViewModifier {
    let ids: [ID]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.animation(
            CrestMotion.collection.unlessReducingMotion(reduceMotion),
            value: ids
        )
    }
}
