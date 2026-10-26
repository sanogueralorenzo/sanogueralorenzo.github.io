import SwiftUI

/// Shared card geometry, appearance, and drag thresholds.
enum BrowserSidebarWidgetDeckStyle {
    /// Selects system glass or the custom material treatment.
    static let usesLiquidGlass = true

    static let cardStrokeWidth: CGFloat = 0.5
    static let edgeHighlightTopOpacity = 0.22
    static let edgeHighlightBottomOpacity = 0.05
    static let contactShadowOpacity = 0.22
    static let contactShadowRadius: CGFloat = 1
    static let contactShadowOffset: CGFloat = 0.5
    static let ambientShadowRadius: CGFloat = 8
    static let ambientShadowOffset: CGFloat = 3
    static let underCardShadowScale = 0.45

    /// Visible slots: the front card plus the two cards it will flip to.
    static let visibleDepth = 3
    static let layerPeek: CGFloat = 6
    static let depthScales: [CGFloat] = [1, 0.965, 0.93]
    static let depthOpacities: [Double] = [1, 0.9, 0.75]
    static let contentOpacities: [Double] = [1, 0.45, 0]
    static let contentMaskFadeStart = 0.55
    static let contentMaskFadeEnd = 0.85

    static let dragTrackingFactor: CGFloat = 0.35
    static let dragRubberBandLimit: CGFloat = 28
    static let dragCommitThreshold: CGFloat = 40

    static let contentSpacing: CGFloat = 10
    static let nowPlayingSectionSpacing: CGFloat = 6
    /// Artwork grows with the platform hit target.
    static var artworkSize: CGFloat {
        max(50, CrestLayout.minimumHitTarget + 12)
    }
    static let artworkCornerRadius: CGFloat = 6
    static let hairlineStrokeOpacity = 0.1
    static let faviconSize = 22.0
    static let focalControlDiameter: CGFloat = 32
    /// Glyph diameter; the surrounding hit target adapts to the platform.
    static let quietControlDiameter: CGFloat = 24
    static let quietControlSymbolSize: CGFloat = 12
    static var quietControlHitTarget: CGFloat {
        max(quietControlDiameter, CrestLayout.minimumHitTarget)
    }
    static let actionHeight: CGFloat = 28
    static let headerTileSize: CGFloat = 30
    static let badgeVerticalPadding: CGFloat = 1
    static let stepperBadgeHorizontalPadding: CGFloat = 2
    static let indicatorDotDiameter: CGFloat = 5
    static let indicatorHitWidth: CGFloat = 24
    static let indicatorHitHeight: CGFloat = 24
    static let indicatorDotHitHeight: CGFloat = 16
    static let sideStepperRailWidth: CGFloat = 24
    /// Places the stepper in the trailing margin without widening the card.
    static let sideStepperExternalOffset = sideStepperOffset(
        cardTrailingInset: BrowserSidebarMetrics.layerInset,
        railWidth: sideStepperRailWidth,
        paneBoundaryWidth: CrestLayout.hairline
    )
    static let indicatorActiveOpacity = 0.72
    static let indicatorInactiveOpacity = 0.3

    /// A card is a top-level sidebar layer, cornered like every other one.
    @MainActor
    static var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: BrowserSidebarMetrics.layerCornerRadius(), style: .continuous)
    }

    /// A glass top-edge highlight that fades into the card's lower border.
    static func edgeHighlight(scale: Double = 1) -> LinearGradient {
        LinearGradient(
            colors: [
                Color.primary.opacity(edgeHighlightTopOpacity * scale),
                Color.primary.opacity(edgeHighlightBottomOpacity * scale),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    static var quietControlSymbolFont: Font {
        .system(size: quietControlSymbolSize, weight: .semibold)
    }

    /// Selection changes tint while indicator geometry stays fixed.
    static func indicatorSize(isSelected _: Bool) -> CGSize {
        CGSize(width: indicatorDotDiameter, height: indicatorDotDiameter)
    }

    /// Centers the stepper between the card edge and the sidebar divider.
    static func sideStepperOffset(
        cardTrailingInset: CGFloat,
        railWidth: CGFloat,
        paneBoundaryWidth: CGFloat
    ) -> CGFloat {
        (railWidth - cardTrailingInset + paneBoundaryWidth) / 2
    }

    static func deckDepth(cardCount: Int) -> Int {
        min(max(cardCount - 1, 0), visibleDepth - 1)
    }

    static func scale(forDepth depth: Int) -> CGFloat {
        depthScales[min(max(depth, 0), depthScales.count - 1)]
    }

    static func opacity(forDepth depth: Int) -> Double {
        depthOpacities[min(max(depth, 0), depthOpacities.count - 1)]
    }

    static func contentOpacity(forDepth depth: Int) -> Double {
        contentOpacities[min(max(depth, 0), contentOpacities.count - 1)]
    }

    /// Masks only the cards behind the active card.
    static func masksContent(forDepth depth: Int) -> Bool {
        depth > 0
    }

    /// Fades rear-card content before it reaches the shared clipping edge.
    static var contentMask: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: .black, location: 0),
                .init(color: .black, location: contentMaskFadeStart),
                .init(color: .clear, location: contentMaskFadeEnd),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    /// Compensates for scale so each rear card exposes the same strip.
    static func slotOffset(forDepth depth: Int, cardHeight: CGFloat?) -> CGFloat {
        guard depth > 0 else { return 0 }
        let peek = layerPeek * CGFloat(depth)
        let shrink = (cardHeight ?? 0) * (1 - scale(forDepth: depth))
        return peek + shrink
    }

    /// Dampens travel beyond the drag limit.
    static func draggedOffset(forTranslation translation: CGFloat) -> CGFloat {
        let tracked = translation * dragTrackingFactor
        let magnitude = abs(tracked)
        guard magnitude > dragRubberBandLimit else { return tracked }
        let excess = magnitude - dragRubberBandLimit
        let damped =
            dragRubberBandLimit + excess / (1 + excess / dragRubberBandLimit)
        return tracked < 0 ? -damped : damped
    }

    /// A negative primary-axis drag flips forward; a positive drag flips back.
    static func dragCommitDirection(
        translation: CGFloat,
        predictedEndTranslation: CGFloat
    ) -> BrowserSidebarWidgetCarouselDirection? {
        let travel: CGFloat
        if abs(translation) >= dragCommitThreshold {
            travel = translation
        } else if abs(predictedEndTranslation) >= dragCommitThreshold {
            travel = predictedEndTranslation
        } else {
            return nil
        }
        return travel < 0 ? .next : .previous
    }
}
