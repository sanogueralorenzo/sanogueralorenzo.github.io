import SwiftUI

/// The whole of a transient overlay below its lock: the scrim, and the card
/// standing on it.
///
/// The card grows out of the link it came from. Where that growth is applied
/// is the one thing the arrangement changes here — a pointer overlay grows the
/// page alone and leaves its controls in place, a touch overlay grows the card
/// and its controls together — and the state hands identity to whichever layer
/// is not growing, so both run the same chain.
struct BrowserTransientSurface<WebContent: View>: View {
    let state: BrowserTransientPresentationState
    let pageStatus: BrowserTransientPageStatus
    let spaces: [BrowserSpaceIdentity]
    let selectedSpaceID: UUID
    let vocabulary: BrowserTransientOverlayVocabulary
    let actions: BrowserTransientCardActions
    @ViewBuilder let webContent: () -> WebContent

    var body: some View {
        // The stack's insets keep the card clear of the safe area, so the
        // surface takes the whole container; laid out inside the safe area
        // as well, the card would keep clear of it twice.
        GeometryReader { safeAreaProxy in
            surface(safeAreaInsets: Self.safeAreaInsets(of: safeAreaProxy))
                .ignoresSafeArea()
        }
    }

    /// The container's safe area, with its top edge below the controls a
    /// resizable iPad window keeps in a top corner. A corner the side's own
    /// inset already clears, such as a status bar beside the page, leaves the
    /// top edge where it is.
    private static func safeAreaInsets(of proxy: GeometryProxy) -> EdgeInsets {
        var insets = proxy.safeAreaInsets
        let corners = proxy.containerCornerInsets
        if corners.topLeading.width > insets.leading {
            insets.top = max(insets.top, corners.topLeading.height)
        }
        if corners.topTrailing.width > insets.trailing {
            insets.top = max(insets.top, corners.topTrailing.height)
        }
        return insets
    }

    private func surface(safeAreaInsets: EdgeInsets) -> some View {
        GeometryReader { proxy in
            ZStack {
                BrowserTransientScrim(
                    opacity: state.scrimOpacity,
                    allowsDismissal: state.arrangement.allowsScrimDismissal,
                    dismiss: actions.dismiss
                )
                BrowserTransientCardStack(
                    state: state,
                    pageStatus: pageStatus,
                    spaces: spaces,
                    selectedSpaceID: selectedSpaceID,
                    vocabulary: vocabulary,
                    availableSize: proxy.size,
                    safeAreaInsets: safeAreaInsets,
                    actions: actions,
                    webContent: webContent
                )
                .scaleEffect(
                    x: assemblyScale.width,
                    y: assemblyScale.height,
                    anchor: state.sourceTransform.anchor
                )
                .opacity(state.opacity(for: .assembly))
            }
            .coordinateSpace(name: BrowserTransientMotion.coordinateSpaceName)
        }
    }

    private var assemblyScale: CGSize {
        state.scale(for: .assembly)
    }
}
