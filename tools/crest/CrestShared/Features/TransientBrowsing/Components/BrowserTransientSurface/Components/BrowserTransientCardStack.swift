import SwiftUI

/// A transient overlay's card and the controls that close or keep it.
///
/// One stack serves every arrangement: the arrangement decides which side of
/// the card the controls sit on and how large the card is allowed to be.
/// Everything an arrangement does not use resolves to identity, so all three
/// walk the same chain.
struct BrowserTransientCardStack<WebContent: View>: View {
    let state: BrowserTransientPresentationState
    let pageStatus: BrowserTransientPageStatus
    let spaces: [BrowserSpaceIdentity]
    let selectedSpaceID: UUID
    let vocabulary: BrowserTransientOverlayVocabulary
    let availableSize: CGSize
    let safeAreaInsets: EdgeInsets
    let actions: BrowserTransientCardActions
    @ViewBuilder let webContent: () -> WebContent

    var body: some View {
        VStack(
            alignment: arrangement.controlAlignment,
            spacing: arrangement.controlSpacing
        ) {
            if arrangement.placesControlsAboveCard {
                actionBar
                pageCard
            } else {
                pageCard
                actionBar
            }
        }
        .padding(arrangement.contentInsets(safeAreaInsets: safeAreaInsets))
        .modifier(BrowserTransientContentRegion(region: contentRegion))
    }

    private var arrangement: BrowserTransientCardArrangement {
        state.arrangement
    }

    private var actionBar: some View {
        BrowserPeekActionBar(
            spaces: spaces,
            selectedSpaceID: selectedSpaceID,
            closeAccessibilityLabel: vocabulary.closeAccessibilityLabel,
            closeHelp: vocabulary.closeHelp,
            dismiss: actions.dismiss,
            openInSpace: actions.promote
        )
        .modifier(BrowserTransientControlBarWidth(arrangement: arrangement))
        .opacity(state.controlsOpacity)
        .allowsHitTesting(state.isCardExpanded)
    }

    private var pageCard: some View {
        BrowserTransientPageCard(
            arrangement: arrangement,
            pageStatus: pageStatus,
            vocabulary: vocabulary,
            reduceMotion: state.reduceMotion,
            reduceTransparency: state.reduceTransparency,
            restore: actions.restore,
            webContent: webContent
        )
        .modifier(BrowserTransientCardSize(size: cardSize))
        .scaleEffect(
            x: pageCardScale.width,
            y: pageCardScale.height,
            anchor: state.sourceTransform.anchor
        )
        .opacity(state.opacity(for: .pageCard))
        .modifier(
            BrowserTransientMotionTransform(
                state: state.motionState, containerSize: availableSize, reduceMotion: state.reduceMotion
            ))
    }

    /// The region the stack is laid out inside, once the shell's own leading
    /// chrome has taken its share. `nil` wherever the overlay owns everything.
    private var contentRegion: CGRect? {
        arrangement.contentFrame(
            in: availableSize,
            reservedLeadingWidth: state.reservedLeadingWidth,
            layoutDirection: state.layoutDirection
        )
    }

    private var cardSize: CGSize? {
        arrangement.cardSize(in: contentRegion?.size ?? availableSize)
    }

    private var pageCardScale: CGSize {
        state.scale(for: .pageCard)
    }
}

// MARK: - Arrangement-shaped layout

/// The arrangement's card size, as far as the room its insets and controls
/// leave allows: a page column beside a tablet's sidebar can be narrower than
/// the card the screen would float.
private struct BrowserTransientCardSize: ViewModifier {
    let size: CGSize?

    func body(content: Content) -> some View {
        if let size {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .frame(maxWidth: size.width, maxHeight: size.height)
        } else {
            content
        }
    }
}

private struct BrowserTransientContentRegion: ViewModifier {
    let region: CGRect?

    func body(content: Content) -> some View {
        if let region {
            content
                .frame(width: region.width, height: region.height)
                .position(x: region.midX, y: region.midY)
        } else {
            content.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct BrowserTransientControlBarWidth: ViewModifier {
    let arrangement: BrowserTransientCardArrangement

    func body(content: Content) -> some View {
        if arrangement.constrainsControlBarToMaximumWidth {
            content
                .frame(maxWidth: BrowserPeekActionBar.width)
                .padding(arrangement.controlBarPadding)
        } else {
            content.frame(width: BrowserPeekActionBar.width)
        }
    }
}
