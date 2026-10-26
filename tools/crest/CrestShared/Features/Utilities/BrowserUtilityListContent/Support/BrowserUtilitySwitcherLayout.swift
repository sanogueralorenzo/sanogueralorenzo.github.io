import CoreGraphics

enum BrowserUtilitySwitcherLayout {
    static let destinations = BrowserUtilitySurface.all
    static let step: CGFloat = 64
    static let buttonSize = CrestLayout.glassIconButtonDiameter
    static let collapsedScale: CGFloat = 0.08
    static let destinationGap: CGFloat = 18
    static let staggerInterval = 0.045
    static let notificationBadgeMinimumSize: CGFloat = 16
    static let notificationBadgeHorizontalPadding: CGFloat = 4
    static let notificationBadgeOffset: CGFloat = 4

    static var expansionSteps: [any BrowserUtilityFanExpansionStep] {
        destinations.enumerated().flatMap { index, surface -> [any BrowserUtilityFanExpansionStep] in
            let reveal = BrowserUtilityFanReveal(surface: surface)
            guard index > 0 else { return [reveal] }
            return [BrowserUtilityFanWait(delay: staggerInterval), reveal]
        }
    }

    static func verticalOffset(for index: Int, count: Int) -> CGFloat {
        (CGFloat(index) - CGFloat(count - 1) / 2) * step
    }

    static func expansionDelay(for index: Int) -> Double {
        Double(max(index, 0)) * staggerInterval
    }
}
