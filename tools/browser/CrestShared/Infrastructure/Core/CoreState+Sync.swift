import Foundation

extension CoreState {
    // MARK: - Variables

    /// Whether the session whose journal syncs is still the disposable seed a
    /// first launch made, which the cloud's content replaces before anything
    /// syncs.
    var syncsDisposableSeed: Bool {
        guard let journal = syncJournal else { return false }
        return workspaces[journal.workspaceID]?.isDisposableSeed == true
    }
}
