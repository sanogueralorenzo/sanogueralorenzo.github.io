import SwiftUI

/// How a failed page lays out its explanation: centered and stacked where it
/// is narrow, leading where there is room.
struct BrowserNavigationFailureLayout: Hashable, Sendable {
    // MARK: - Static Variables

    static let compact = BrowserNavigationFailureLayout(
        name: "compact", contentAlignment: .center, frameAlignment: .center, textAlignment: .center,
        horizontalPadding: 24, verticalPadding: 44, stacksActions: true)
    static let regular = BrowserNavigationFailureLayout(
        name: "regular", contentAlignment: .leading, frameAlignment: .leading, textAlignment: .leading,
        horizontalPadding: 48, verticalPadding: 72, stacksActions: false)

    // MARK: - Variables

    let name: String
    let contentAlignment: HorizontalAlignment
    let frameAlignment: Alignment
    let textAlignment: TextAlignment
    let horizontalPadding: CGFloat
    let verticalPadding: CGFloat

    /// Whether the actions stand one above another at full width.
    let stacksActions: Bool

    // MARK: - Initializers

    private init(
        name: String, contentAlignment: HorizontalAlignment, frameAlignment: Alignment, textAlignment: TextAlignment,
        horizontalPadding: CGFloat, verticalPadding: CGFloat, stacksActions: Bool
    ) {
        self.name = name
        self.contentAlignment = contentAlignment
        self.frameAlignment = frameAlignment
        self.textAlignment = textAlignment
        self.horizontalPadding = horizontalPadding
        self.verticalPadding = verticalPadding
        self.stacksActions = stacksActions
    }

    // MARK: - Actions - Identity

    static func == (lhs: BrowserNavigationFailureLayout, rhs: BrowserNavigationFailureLayout) -> Bool {
        lhs.name == rhs.name
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
    }
}
