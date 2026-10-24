import Foundation

/// Where a window stands in what it shows: the revision the read model gives
/// its workspace's session, or nil once the core closed the workspace, and
/// how many times the window itself showed something else. It moves whenever
/// either does, so a reader that follows the window as a whole, such as its
/// page host, hears each change once.
struct BrowserSessionRevision: Equatable, Sendable {
    // MARK: - Variables

    let session: UInt64?
    let window: Int
}

/// How a window starts in the core's device: its identity, whether it keeps
/// its record across launches, the window it starts as when it has no record,
/// and what it shows first. Only a window over the session the core keeps in
/// its file keeps a record; elsewhere `saved` has no effect.
struct BrowserWindowOpening {
    var id = UUID()
    var saved = false
    var copying: UUID?
    var showingSpaceID: UUID?
    var showingTabs: [UUID: UUID] = [:]
    /// False keeps only the Space the window starts on, showing no tab.
    var restoresTabs = true
}
