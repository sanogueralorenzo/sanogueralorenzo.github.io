import Foundation

extension ClosePage {
    /// The page leaves the engine only when this engine still hosts it.
    func note(runningOn kind: EngineKind, in hosts: inout [UUID: EngineKind]) {
        if hosts[pageID] == kind { hosts[pageID] = nil }
    }
}
