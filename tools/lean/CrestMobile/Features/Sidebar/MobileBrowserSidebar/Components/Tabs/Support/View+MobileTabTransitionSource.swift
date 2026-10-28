import SwiftUI

extension View {
    /// Registers this row as the source of the system's navigation zoom.
    ///
    /// Only that. The matched-geometry end of a promotion is the shared row's to
    /// decide — `BrowserInteractionCapabilities.usesMatchedGeometryPromotionDestination`
    /// — and this seam supplying it too is what gave one identity two anchors on
    /// the placements that have no native zoom.
    @ViewBuilder
    func mobileTabTransitionSource(
        id: String,
        in namespace: Namespace.ID?,
        usesNativeNavigationTransition: Bool,
        isEnabled: Bool
    ) -> some View {
        if let namespace, isEnabled, usesNativeNavigationTransition {
            matchedTransitionSource(id: id, in: namespace)
        } else {
            self
        }
    }
}
