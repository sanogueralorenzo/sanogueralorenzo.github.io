import Foundation

extension AdoptOfferedPage {
    /// The adopted page is the engine's until it closes.
    func note(runningOn kind: EngineKind, in hosts: inout [UUID: EngineKind]) {
        hosts[pageID] = kind
    }
}
