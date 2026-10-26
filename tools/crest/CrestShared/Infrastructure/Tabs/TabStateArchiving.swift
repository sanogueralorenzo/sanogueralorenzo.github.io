import Dispatch
import Foundation

/// Stores each tab's engine history on disk, so a tab that lost its page to a
/// relaunch comes back with its back/forward list and scroll positions instead
/// of a bare reload. The core hands a page it unloads back its state within a
/// run, but keeps it in memory only, never in a saved file, so this archive is
/// what survives a relaunch.
///
/// Blobs run to hundreds of kilobytes, so they are kept out of the session JSON
/// and written as one file per tab, off the main thread. Nothing here decides
/// *whether* a tab may be archived: private and disposable runtimes are given no
/// archive at all, so they cannot write one by accident.
protocol BrowserTabStateArchiving: AnyObject, Sendable {
    /// The framed envelope stored for one tab, or nil when there is none.
    func archivedState(profileID: UUID, tabID: UUID) -> Data?
    /// Keeps the tab's engine history as showing `url`, with its back and
    /// forward history as the core keeps it across engines, when it has one.
    func archive(interactionState: Data, url: URL?, history: Data?, profileID: UUID, tabID: UUID)
    func removeState(profileID: UUID, tabID: UUID)
    /// Drops every state belonging to one profile. Space deletion calls this, so
    /// per-Space isolation survives a Space being deleted.
    func removeStates(profileID: UUID)
    /// Drops states for tabs a profile no longer has, current or archived.
    /// Profiles absent from the map are left untouched.
    func pruneStates(keeping tabIDsByProfileID: [UUID: Set<UUID>])
    func flushPendingWrites() async
}
