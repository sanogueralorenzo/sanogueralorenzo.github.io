import CoreGraphics

enum BrowserSplitPanelLayoutMetrics {
    static let defaultWidth: CGFloat = 360
    static let minimumWidth: CGFloat = 280
    static let maximumWidth: CGFloat = 600

    static func clampedWidth(_ width: CGFloat) -> CGFloat {
        guard width.isFinite else { return defaultWidth }
        return min(max(width, minimumWidth), maximumWidth)
    }
}

/// A panel reserves points, not a share of tab fractions. When a narrow window
/// cannot fit everything, the panel yields before any member reaches its floor.
enum BrowserSplitPanelLayout {
    static func resolvedWidth(
        requestedWidth: CGFloat, containerWidth: CGFloat, memberCount: Int,
        gap: CGFloat = BrowserSplitLayoutMetrics.interCardGap
    ) -> CGFloat {
        guard memberCount > 0, containerWidth.isFinite else { return 0 }
        let memberMinimum = CGFloat(memberCount) * BrowserSplitLayoutMetrics.minimumCardWidth
        let gaps = CGFloat(memberCount) * gap
        return max(
            0,
            min(
                BrowserSplitPanelLayoutMetrics.clampedWidth(requestedWidth),
                containerWidth - memberMinimum - gaps
            ))
    }

    static func memberContainerWidth(
        containerWidth: CGFloat, panelWidth: CGFloat,
        gap: CGFloat = BrowserSplitLayoutMetrics.interCardGap
    ) -> CGFloat {
        guard containerWidth.isFinite, panelWidth.isFinite else { return 0 }
        return max(0, containerWidth - panelWidth - gap)
    }

    static func widthAfterResize(initialWidth: CGFloat, delta: CGFloat) -> CGFloat {
        guard delta.isFinite else { return BrowserSplitPanelLayoutMetrics.clampedWidth(initialWidth) }
        return BrowserSplitPanelLayoutMetrics.clampedWidth(initialWidth - delta)
    }
}
