import Foundation

extension CloudTransportChanged {
    /// Receipts for the cloud transport about its own state, which only the
    /// transport reads.
    @MainActor func apply(to state: CoreState) {}

    /// The transport keeps the last state the core answered.
    func note(in receipts: inout CloudTransportReceipts) {
        receipts.transport = state
    }
}
