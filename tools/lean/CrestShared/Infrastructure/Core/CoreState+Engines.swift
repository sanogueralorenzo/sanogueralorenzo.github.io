import Foundation

extension CoreState {
    /// WebKit capabilities available to commands and settings. Before registration,
    /// leave the initial UI available as Crest does during composition.
    func offers(_ capability: EngineCapability) -> Bool {
        engines?.offered.contains(capability) ?? true
    }
}
