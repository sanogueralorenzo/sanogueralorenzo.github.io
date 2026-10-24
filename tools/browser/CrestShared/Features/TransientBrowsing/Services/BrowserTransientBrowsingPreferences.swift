import Foundation

@MainActor
struct BrowserTransientBrowsingPreferences {
    // MARK: - Static Variables

    static let isolated = BrowserTransientBrowsingPreferences(
        archiveLifetime: nil,
        rememberSpace: { _, _ in }
    )

    // MARK: - Variables

    private let lifetime: () -> TimeInterval?
    private let rememberSpaceHandler: (UUID, URL) -> Void

    /// How long an inactive Quick Window stays open, read each time it is
    /// asked, so a changed preference reaches windows already open.
    var archiveLifetime: TimeInterval? { lifetime() }

    // MARK: - Initializers

    init(
        archiveLifetime: @escaping () -> TimeInterval?,
        rememberSpace: @escaping (UUID, URL) -> Void
    ) {
        lifetime = archiveLifetime
        rememberSpaceHandler = rememberSpace
    }

    init(
        archiveLifetime: TimeInterval?,
        rememberSpace: @escaping (UUID, URL) -> Void
    ) {
        self.init(archiveLifetime: { archiveLifetime }, rememberSpace: rememberSpace)
    }

    // MARK: - Actions - Spaces

    func rememberSpace(_ spaceID: UUID, for url: URL) {
        rememberSpaceHandler(spaceID, url)
    }
}

/// When an inactive Quick Window archives itself: after its latest activity,
/// once its lifetime passes. A view restarts its wait whenever either changes.
struct BrowserTransientArchiveTimer: Hashable {
    let activity: Int
    let lifetime: TimeInterval?
}
