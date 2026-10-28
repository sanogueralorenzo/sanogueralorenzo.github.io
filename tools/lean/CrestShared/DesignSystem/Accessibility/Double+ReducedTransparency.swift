import Foundation

extension Double {
    // MARK: - Static Variables

    private static let reducedTransparencyScrimOpacity = 0.56

    // MARK: - Actions - Accessibility

    /// This custom scrim opacity, raised to a solid enough floor while the
    /// system asks to reduce transparency.
    func scrimOpacity(reduceTransparency: Bool) -> Double {
        reduceTransparency
            ? Swift.max(self, Self.reducedTransparencyScrimOpacity)
            : self
    }
}
