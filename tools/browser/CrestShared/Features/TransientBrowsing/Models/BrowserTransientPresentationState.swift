import SwiftUI

/// Everything a transient overlay's surface needs to draw one frame of itself.
///
/// The shell owns the state that changes — whether the card has appeared, how
/// far into its entrance it is, what the person's accessibility settings ask
/// for — and hands it over as a value. The derivations below are the same on
/// every shell; the arrangement decides which of them are live and which
/// resolve to identity, so both shells run one chain rather than two.
struct BrowserTransientPresentationState {
    let arrangement: BrowserTransientCardArrangement
    /// Width the shell's own leading chrome has already claimed. Zero wherever
    /// the overlay owns the whole screen.
    var reservedLeadingWidth: CGFloat = 0
    var layoutDirection: LayoutDirection = .leftToRight
    let isCardVisible: Bool
    let isCardExpanded: Bool
    let reduceMotion: Bool
    let reduceTransparency: Bool
    /// Staged only where a press can hold an overlay open before committing to
    /// it. A shell without that gesture is always committed.
    var presentationPhase: BrowserPeekPresentationPhase = .committed
    let sourcePresentation: BrowserPeekSourcePresentation
    var motionState: BrowserPeekMotionState? = nil

    var sourceTransform: BrowserTransientSourceTransform {
        BrowserTransientCardLayout.sourceCardTransform(for: sourcePresentation)
    }

    // MARK: - Growing out of the source link

    /// The entrance scale, applied to whichever layer the arrangement grows.
    /// The other layer is handed identity, so both shells run the same chain.
    func scale(for target: BrowserTransientEntranceTarget) -> CGSize {
        if motionState != nil { return CGSize(width: 1, height: 1) }
        guard arrangement.entranceTarget == target else {
            return CGSize(width: 1, height: 1)
        }
        return CGSize(width: cardScaleX, height: cardScaleY)
    }

    func opacity(for target: BrowserTransientEntranceTarget) -> Double {
        arrangement.entranceTarget == target ? cardOpacity : 1
    }

    var controlsOpacity: Double {
        isCardExpanded ? 1 : 0
    }

    // MARK: - The scrim behind it

    /// The scrim rests dimmer while the overlay is only staged behind a press,
    /// and is absent until the card itself is on screen.
    var scrimOpacity: Double {
        // Pulling the card provides the emphasis without dimming the source.
        guard motionState == nil else { return 0 }
        let restingOpacity = presentationPhase == .staged ? 0.08 : 0.34
        return (restingOpacity * (isCardVisible ? 1 : 0)).scrimOpacity(reduceTransparency: reduceTransparency)
    }

    // MARK: - Derivations behind the entrance

    private var cardOpacity: Double {
        isCardExpanded || isCardVisible ? 1 : 0
    }

    private var cardScaleX: CGFloat {
        cardScale(
            visible: sourceTransform.scaleX,
            staged: sourceTransform.scaleX * 0.82
        )
    }

    private var cardScaleY: CGFloat {
        cardScale(
            visible: sourceTransform.scaleY,
            staged: sourceTransform.scaleY * 0.82
        )
    }

    /// A card that has finished growing is at its own size. Before that it is
    /// the size of the link it came from, or smaller again while it waits
    /// behind a press that has not committed.
    private func cardScale(visible: CGFloat, staged: CGFloat) -> CGFloat {
        guard !isCardExpanded else { return 1 }
        return (isCardVisible ? visible : staged).unlessReducingMotion(reduceMotion)
    }
}
