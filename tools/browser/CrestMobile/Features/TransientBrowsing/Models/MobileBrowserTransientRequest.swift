import Foundation
import SwiftUI

// MARK: - Types

struct MobileBrowserTransientRenderIdentity: Hashable {
    let requestID: UUID
    let url: URL
    let assignment: BrowserSpaceRuntimeAssignment
    let isQuickWindow: Bool
}

/// A Peek or a Quick Window the mobile overlay presents. Each request says
/// how it is shown, and what dismissing it, selecting another Space and
/// letting its page go do, so the overlay asks the request instead of asking
/// which one it is.
@MainActor
protocol MobileBrowserTransientRequest: Equatable, Sendable {
    var id: UUID { get }
    var url: URL { get }
    var spaceID: UUID { get }
    var spaceAssignment: BrowserSpaceRuntimeAssignment { get }
    var sourcePresentation: BrowserPeekSourcePresentation? { get }
    var isQuickWindow: Bool { get }
    var accessibilityLabel: String { get }
    var accessibilityIdentifier: String { get }
    /// The symbol the overlay's preview shows for this request.
    var previewSystemImage: String { get }

    /// What this shell calls the shared overlay presenting this request.
    ///
    /// One card serves both, so the words are the only thing that separates a
    /// Peek from a Quick Window here. The restore button stays neutral because
    /// what it brings back is the page, under either name.
    var overlayVocabulary: BrowserTransientOverlayVocabulary { get }

    func motionState(in coordinator: BrowserTransientBrowsingCoordinator) -> BrowserPeekMotionState?
    func isSelected(in browser: BrowserStore) -> Bool
    func hasSource(in browser: BrowserStore) -> Bool
    func isPresented(by coordinator: BrowserTransientBrowsingCoordinator) -> Bool

    /// Takes the request off screen, keeping nothing of its page.
    func dismiss(from coordinator: BrowserTransientBrowsingCoordinator)

    /// Takes the request off screen when the person closes it or keeps its page.
    func close(on overlay: MobileBrowserTransientOverlayModel)

    /// A lease on a new page for this request in `space`.
    func makePageLease(
        for overlay: MobileBrowserTransientOverlayModel,
        from pages: MobileBrowserPageStore,
        in space: SpaceModel
    ) -> MobileBrowserTransientPageLease?

    /// Notes that the person kept `page` as a tab in `destinationAssignment`.
    func rememberKeeping(
        _ page: MobileBrowserPage,
        in destinationAssignment: BrowserSpaceRuntimeAssignment,
        preferences: BrowserTransientBrowsingPreferences
    )

    func selectLockedSpace(_ assignment: BrowserSpaceRuntimeAssignment, on overlay: MobileBrowserTransientOverlayModel)

    /// Lets `lease`'s page go.
    func release(_ lease: MobileBrowserTransientPageLease, on overlay: MobileBrowserTransientOverlayModel)

    /// Lets the page go when the overlay leaves the screen.
    func disappear(from overlay: MobileBrowserTransientOverlayModel)
}

extension MobileBrowserTransientRequest {
    // MARK: - Variables

    var resolvedSourcePresentation: BrowserPeekSourcePresentation {
        BrowserPeekSourcePresentation.resolved(sourcePresentation)
    }

    var renderIdentity: MobileBrowserTransientRenderIdentity {
        MobileBrowserTransientRenderIdentity(
            requestID: id,
            url: url,
            assignment: spaceAssignment,
            isQuickWindow: isQuickWindow
        )
    }

    // MARK: - Actions - Identity

    /// Whether `other` is this same request.
    nonisolated func matches(_ other: any MobileBrowserTransientRequest) -> Bool {
        (other as? Self) == self
    }
}
