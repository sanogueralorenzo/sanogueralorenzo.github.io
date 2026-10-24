import Foundation

extension ShortcutsChanged {
    /// The core publishes every offered command's binding at once.
    @MainActor func apply(to state: CoreState) {
        state.shortcutBindings = bindings
        state.shortcuts = Dictionary(bindings.map { ($0.command, $0) }, uniquingKeysWith: { first, _ in first })
        state.shortcutsAreCustomized = isCustomized
    }
}
