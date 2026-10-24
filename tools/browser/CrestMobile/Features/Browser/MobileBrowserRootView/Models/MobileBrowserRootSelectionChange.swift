import Foundation

/// What changed between two selections a window shows, the widest first.
enum MobileBrowserRootSelectionChange: Equatable, Sendable {
    case unchanged
    case tab
    case space
    case profile

    static func resolve(
        from previous: MobileBrowserRootSelectionSnapshot,
        to current: MobileBrowserRootSelectionSnapshot
    ) -> Self {
        if previous.selectedSpaceID != current.selectedSpaceID {
            return .space
        }
        if previous.selectedProfileID != current.selectedProfileID {
            return .profile
        }
        if previous.assignment?.tabID != current.assignment?.tabID {
            return .tab
        }
        return .unchanged
    }
}
