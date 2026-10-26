/// Which way one arrow press or accessibility step turns a Space's gradient.
struct BrowserSpaceGradientAngleAdjustmentDirection: Equatable {
    // MARK: - Static Variables

    static let gradientAngleStep = 15.0

    static let increment = BrowserSpaceGradientAngleAdjustmentDirection(name: "increment", delta: gradientAngleStep)
    static let decrement = BrowserSpaceGradientAngleAdjustmentDirection(name: "decrement", delta: -gradientAngleStep)

    // MARK: - Variables

    let name: String

    /// How many degrees one step this way turns the gradient.
    private let delta: Double

    // MARK: - Actions - Adjusting

    /// `angle` turned one step this way, kept within a single turn.
    func adjusted(_ angle: Double) -> Double {
        let remainder = (angle + delta).truncatingRemainder(dividingBy: 360)
        return remainder >= 0 ? remainder : remainder + 360
    }
}
