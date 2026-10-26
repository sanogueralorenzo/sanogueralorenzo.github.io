import CoreGraphics
import Foundation

/// What a content area is presenting: a row of cards, or the one page surface.
///
/// Resolved by `init(space:isLocked:cards:…)` and then only drawn, so a shell
/// reads the branch rather than deciding it.
@MainActor
enum BrowserPageSurfacePresentation {
    /// The single surface with no Space of its own behind it — none is
    /// selected, or the selected one is locked and showing its access gate
    /// instead of pages. Nothing may be dropped into it: the page store has
    /// already let every card go, and a Space that has not been unlocked is not
    /// somewhere a tab may land.
    case unavailable

    /// The single rounded surface, presenting `space`. `cardTabID` is the lone
    /// tab a drag can drop beside — what a dropped tab would join, and the side
    /// of it the pointer is on is which side the new card lands.
    case single(space: SpaceModel, cardTabID: UUID?)

    /// A row of cards. `placeholderIndex` is the slot a drag in flight would
    /// drop into, or `nil` when no drop is resolved against this row.
    case columns(space: SpaceModel, members: [TabStateModel], placeholderIndex: Int?)

    // MARK: - Static Variables

    private nonisolated static let startPageUsesSpaceAtmosphere = true
    private nonisolated static let startPageUsesTransparentInnerSurface = true

    // MARK: - Initializers

    /// The decision a content area makes before it draws anything: columns or
    /// the single page surface, and for which Space.
    ///
    /// Written once because both shells were writing it, and a disagreement is
    /// not cosmetic — the two layouts host the live web view in different
    /// places, so a shell that opens columns one condition earlier than the
    /// other rebuilds a page's host where the other does not. Which tabs are
    /// cards is the core's: the window's `cards(in:)`.
    ///
    /// - Parameters:
    ///   - cards: The tabs the window shows side by side in `space`.
    ///   - hasEnteredSplitContent: Whether a drag has already reached the
    ///     content area during this lift. It holds the columns layout open
    ///     around a single presented tab for the rest of the drag rather than
    ///     following the pointer back and forth, because every flip between the
    ///     two layouts hands the live web view to a different host, while the
    ///     placeholder coming and going inside the columns layout is only a
    ///     width change.
    ///   - resolvedTarget: Where the lift in flight would land. Only a
    ///     `.splitInsert` aimed at this very Space opens a slot in this row.
    init(
        space: SpaceModel?,
        isLocked: Bool,
        cards: [TabStateModel],
        hasEnteredSplitContent: Bool,
        resolvedTarget: BrowserSidebarReorderTarget?,
        presentsTrailingPanel: Bool = false
    ) {
        guard let space, !isLocked else {
            self = .unavailable
            return
        }
        guard !cards.isEmpty, cards.count > 1 || hasEnteredSplitContent || presentsTrailingPanel else {
            self = .single(space: space, cardTabID: cards.first?.id)
            return
        }
        self = .columns(
            space: space, members: cards,
            placeholderIndex: Self.placeholderIndex(resolvedTarget: resolvedTarget, spaceID: space.id))
    }

    // MARK: - Variables

    /// The Space whose cards this window is showing, or `nil` when there are
    /// none to show.
    var presentingSpace: SpaceModel? {
        switch self {
        case .unavailable: nil
        case .single(let space, _): space
        case .columns(let space, _, _): space
        }
    }

    /// The Space a drag over the content area resolves against — the presented
    /// one, so a card lands in the Space it was dropped on rather than the one
    /// whose sidebar the drag started in.
    var dropAssignment: BrowserSpaceRuntimeAssignment? {
        presentingSpace.map(BrowserSpaceRuntimeAssignment.init(space:))
    }

    /// The tab the single surface is showing, when there is one to drop beside.
    var singleCardTabID: UUID? {
        guard case .single(_, let cardTabID) = self else { return nil }
        return cardTabID
    }

    /// The single surface's captured tab, not a later window selection that
    /// may already belong to a different layout while this surface disappears.
    var singleTab: TabStateModel? {
        guard case .single(let space, let tabID) = self, let tabID else { return nil }
        return space.tabs.model(tabID)
    }

    // MARK: - Actions - Surface

    /// Whether the card lets the Space's atmosphere through instead of
    /// drawing its own background. A page's first load keeps the card's
    /// background: letting the atmosphere through until the page drew flashed
    /// it between every page and the next.
    nonisolated static func usesTransparentInnerSurface(
        isStartPage: Bool,
        hasActivePage: Bool,
        completedNavigationCount: Int
    ) -> Bool {
        (startPageUsesSpaceAtmosphere
            && startPageUsesTransparentInnerSurface
            && isStartPage)
            || !hasActivePage
    }

    /// Whether a page's web content shows yet: not before its first commit.
    nonisolated static func revealsWebContent(committedNavigationCount: Int) -> Bool {
        committedNavigationCount > 0
    }

    /// How far along the loading bar draws for a page's `estimatedProgress`.
    nonisolated static func loadingProgress(
        estimatedProgress: Double,
        isNavigating: Bool
    ) -> CGFloat {
        guard isNavigating else { return 0 }
        return CGFloat(min(max(estimatedProgress, 0.04), 1))
    }

    /// The slot a drag in flight would drop a card into, for this Space.
    private static func placeholderIndex(resolvedTarget: BrowserSidebarReorderTarget?, spaceID: UUID) -> Int? {
        guard case .splitInsert(let assignment, let index) = resolvedTarget?.kind, assignment.spaceID == spaceID
        else { return nil }
        return index
    }
}
