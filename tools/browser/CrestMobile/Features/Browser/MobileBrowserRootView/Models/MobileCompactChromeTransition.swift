import CoreGraphics

/// What a vertical drag on the compact chrome brings up: the tab viewer from
/// the page, or the page from the tab viewer. Each transition says how far the
/// drag must travel, and which way, and what finishing it does.
struct MobileCompactChromeTransition: Equatable, Sendable {
    // MARK: - Static Variables

    static let completionThreshold: CGFloat = 64
    static let verticalDominance: CGFloat = 1.2

    /// An upward drag from the page brings the sidebar up.
    static let revealTabViewer = MobileCompactChromeTransition(
        name: "revealTabViewer", direction: -1, finishes: { $0.revealSidebarFromCompactChrome() })
    /// A downward drag from the tab viewer brings the page back.
    static let revealPage = MobileCompactChromeTransition(
        name: "revealPage", direction: 1, finishes: { $0.model.activateSelectedTab() })

    // MARK: - Variables

    let name: String
    /// The sign of the vertical travel that commits: negative is upward.
    private let direction: CGFloat
    private let finishes: @MainActor @Sendable (MobileBrowserRootContent) -> Void

    // MARK: - Initializers

    private init(
        name: String,
        direction: CGFloat,
        finishes: @escaping @MainActor @Sendable (MobileBrowserRootContent) -> Void
    ) {
        self.name = name
        self.direction = direction
        self.finishes = finishes
    }

    // MARK: - Actions - Gesture

    /// Whether a drag ending at `predictedEndTranslation` commits: mostly
    /// vertical, and past the threshold in this transition's direction.
    func commits(predictedEndTranslation: CGSize) -> Bool {
        guard
            abs(predictedEndTranslation.height)
                > abs(predictedEndTranslation.width) * Self.verticalDominance
        else {
            return false
        }
        return predictedEndTranslation.height * direction >= Self.completionThreshold
    }

    /// Does what a committed drag asks of `content`.
    @MainActor
    func finish(in content: MobileBrowserRootContent) {
        finishes(content)
    }

    // MARK: - Actions - Identity

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.name == rhs.name
    }
}
