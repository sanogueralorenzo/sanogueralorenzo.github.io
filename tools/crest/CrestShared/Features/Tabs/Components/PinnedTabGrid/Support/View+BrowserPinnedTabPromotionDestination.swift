import SwiftUI

extension View {
    /// Applies the promotion anchor a pinned tile claims, and only that one.
    ///
    /// Which anchor — or none — is `BrowserPinnedTabPromotionAnchor`'s to decide;
    /// this is the seam that puts the answer on the view. Keeping the decision
    /// out of here is what stops the rule being re-derived as "anything but the
    /// native zoom", which is how a partnerless matched-geometry anchor came to
    /// sit over the very view the system drag interaction lifts.
    @ViewBuilder
    func browserPinnedTabPromotionDestination(
        id: String,
        in namespace: Namespace.ID?,
        anchor: BrowserPinnedTabPromotionAnchor
    ) -> some View {
        if let namespace {
            switch anchor {
            case .navigationZoomSource:
                matchedTransitionSource(id: id, in: namespace)
            case .matchedGeometryDestination:
                matchedGeometryEffect(
                    id: id,
                    in: namespace,
                    properties: .frame,
                    anchor: .center,
                    isSource: false
                )
            case .none:
                self
            }
        } else {
            self
        }
    }
}
