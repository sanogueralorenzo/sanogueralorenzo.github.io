import SwiftUI

extension View {
    func crestCollectionMotion<ID: Hashable>(ids: [ID]) -> some View {
        modifier(CrestCollectionMotionModifier(ids: ids))
    }

    func crestCollectionItemTransition() -> some View {
        transition(.opacity)
    }
}
