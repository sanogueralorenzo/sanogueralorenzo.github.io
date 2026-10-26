import Foundation

@testable import Crest

extension BrowserStore {
    /// Whether this window's session is the one whose journal syncs: only the
    /// session the core keeps in its file does.
    var syncsSession: Bool {
        core.state.syncJournal?.workspaceID == family.workspaceID
    }
}
