import Foundation

extension EnginesChanged {
    @MainActor func apply(to state: CoreState) {
        state.engines = roster
    }
}
