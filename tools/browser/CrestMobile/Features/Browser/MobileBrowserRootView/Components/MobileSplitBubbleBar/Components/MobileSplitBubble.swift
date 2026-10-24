import SwiftUI

/// One card of a Split View as a favicon bubble beside the address bar, drawn
/// as far from the bar as `distance` says: 1 where the bubble rests a gap
/// away, shrinking into the bar's edge toward 0 as it merges, and peeking out
/// smaller from behind the resting bubble beyond 1, as part of a stack.
struct MobileSplitBubble: View {
    // MARK: - Static Variables

    static var diameter: CGFloat { CrestLayout.minimumHitTarget }
    /// How far a bubble rests from the bar.
    static var gap: CGFloat { MobileBrowserChromeLayout.compactToolbarSpacing }
    /// How far each card of a stack peeks out past the one in front of it.
    static var stackPeek: CGFloat { 10 }
    /// The favicon's size inside the bubble.
    private static var iconSize: CGFloat { 22 }
    /// How small a bubble is once it has merged into the bar.
    private static var mergedScale: CGFloat { 0.5 }
    /// How much smaller each card of a stack is than the one in front of it.
    private static var stackShrink: CGFloat { 0.12 }

    // MARK: - Variables

    let card: TabStateModel
    let favicons: FaviconAssets
    let profileID: UUID?
    let distance: CGFloat
    /// The bubble rests beside the bar rather than in a stack, so it answers
    /// a tap and VoiceOver.
    let isNearest: Bool
    /// Moves the bar to this bubble's card.
    let show: () -> Void

    // MARK: - Actions - Presentation

    var body: some View {
        Button(action: show) {
            TabStateFaviconView(tab: card, favicons: favicons, profileID: profileID, size: Self.iconSize)
                .opacity(iconOpacity)
                .frame(width: Self.diameter, height: Self.diameter)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
        .scaleEffect(scale)
        .allowsHitTesting(isNearest && distance >= 1)
        .accessibilityLabel(card.shownTitle)
        .accessibilityHidden(!isNearest)
    }

    /// How far the bubble's edge nearest the bar sits out past the bar's own
    /// edge, as an offset from where the bar's edge would hold it: inside the
    /// bar, merged, at 0, a gap out at rest, and a peek further per card
    /// stacked in front of it.
    var reach: CGFloat {
        let radius = Self.diameter / 2
        let center =
            distance <= 1
            ? -radius + (Self.gap + Self.diameter) * distance
            : Self.gap + radius + (distance - 1) * Self.stackPeek
        return center + radius
    }

    private var scale: CGFloat {
        distance <= 1
            ? Self.mergedScale + (1 - Self.mergedScale) * distance
            : 1 - Self.stackShrink * (distance - 1)
    }

    /// The favicon fades as the bubble merges, so the bar takes the card's
    /// place before the bubble is gone.
    private var iconOpacity: Double {
        Double(min(1, max(0, (distance - 0.25) / 0.5)))
    }
}
