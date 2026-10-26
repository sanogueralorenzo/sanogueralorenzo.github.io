enum BrowserSpaceSwipeDirection: Equatable, Sendable {
    case previous
    case next

    // MARK: - Variables

    /// The core's direction for a step this way.
    var core: AdjacentDirection {
        switch self {
        case .previous: .previous
        case .next: .next
        }
    }
}
