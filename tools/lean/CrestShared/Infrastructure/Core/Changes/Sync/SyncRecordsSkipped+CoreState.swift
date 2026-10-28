import Foundation

extension SyncRecordsSkipped {
    /// A receipt for the cloud transport, which reports what it skipped; the
    /// read model keeps nothing of it.
    @MainActor func apply(to state: CoreState) {}

    /// Tells the transport what the merge skipped. The first such receipt in
    /// an answer stands.
    func note(in receipts: inout CloudTransportReceipts) {
        if receipts.skipped == nil { receipts.skipped = self }
    }
}
