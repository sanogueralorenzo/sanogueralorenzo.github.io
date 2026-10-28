import Foundation

extension CloudMergeBegan {
    @MainActor func apply(to state: CoreState) {}

    /// Names the merge the core began for the transport.
    func note(in receipts: inout CloudTransportReceipts) {
        receipts.mergeID = mergeID
    }
}
