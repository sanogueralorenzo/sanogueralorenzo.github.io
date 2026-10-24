import SwiftUI

extension View {
    /// Anchors this view to the identity its page grows out of.
    ///
    /// The row is the destination rather than the source: the page is what
    /// moves, and the row is the place it moves from. A shell whose page
    /// arrives through the system's own navigation zoom registers the pairing
    /// there instead and passes `isActive: false`, so one identity never has
    /// two anchors competing for it.
    @ViewBuilder
    func browserTabPromotionDestination(
        id: String,
        in namespace: Namespace.ID?,
        isActive: Bool = true
    ) -> some View {
        if let namespace, isActive {
            matchedGeometryEffect(
                id: id,
                in: namespace,
                properties: .frame,
                anchor: .center,
                isSource: false
            )
        } else {
            self
        }
    }
}
