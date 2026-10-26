import Foundation

extension SetupFinished {
    /// Finishing is answered to the call that finished setup, which opens
    /// the guide; the read model holds nothing of it.
    @MainActor func apply(to state: CoreState) {}
}
