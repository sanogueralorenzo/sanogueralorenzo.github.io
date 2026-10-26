/// The one promotion anchor a pinned tile may claim, given what its shell can
/// actually pair with.
///
/// This exists because both anchors are presentation transforms over the exact
/// view `PinnedTabDragModifier` hands to the system drag interaction. A tile
/// takes at most one, and only where there is something on the other end of it.
/// An anchor with no partner is not merely wasted — it moves the drag source out
/// from under the interaction that lifts it.
///
/// A pinned tile asks the same question a tab row asks, so it delegates to the
/// same answer: `BrowserInteractionCapabilities.usesMatchedGeometryPromotionDestination`.
/// Reading that question as "anything but the native zoom" is exactly what left
/// every tile on the compact shell's docked and floating sidebars wearing a
/// partnerless matched-geometry anchor — the defect tab rows carried until the
/// pairing requirement was made explicit, still live on the tiles because they
/// take a different route to the same modifier. The tab viewer, which does drive
/// the native zoom, was never affected, which is what made a pinned tab's dead
/// drag look like a mystery of its own.
enum BrowserPinnedTabPromotionAnchor: Equatable, Sendable {
    /// Nothing. The tile is left exactly as it lays out.
    case none
    /// The tile is where the system's navigation zoom grows the page out of.
    case navigationZoomSource
    /// The tile is the destination end of a matched-geometry pairing with a
    /// surface that rises out of it.
    case matchedGeometryDestination

    // MARK: - Initializers

    /// The anchor a tile claims.
    init(
        hasNamespace: Bool,
        isTransitionSource: Bool,
        capabilities: BrowserInteractionCapabilities
    ) {
        guard hasNamespace else {
            self = .none
            return
        }
        if capabilities.usesNativeNavigationTransition {
            // Only the tile the page is actually zooming out of. Marking every
            // tile as a source is two answers to one question again.
            self = isTransitionSource ? .navigationZoomSource : .none
            return
        }
        let pairsWithASurfaceThatRisesOutOfIt = capabilities.usesMatchedGeometryPromotionDestination
        self =
            pairsWithASurfaceThatRisesOutOfIt
            ? .matchedGeometryDestination
            : .none
    }
}
