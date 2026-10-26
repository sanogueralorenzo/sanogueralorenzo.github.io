import Foundation

extension CreatePage {
    /// The page is the engine's until it closes.
    func note(runningOn kind: EngineKind, in hosts: inout [UUID: EngineKind]) {
        hosts[pageID] = kind
    }
}
