import Foundation

/// What the core's answer to one of the cloud transport's intents tells the
/// transport. Each change in the answer notes its own part.
struct CloudTransportReceipts {
    // MARK: - Variables

    /// The transport's state, as the core last answered it.
    var transport: CloudTransportState?
    /// The merge the core began.
    var mergeID: Int64?
    /// What a merge of downloaded records skipped.
    var skipped: SyncRecordsSkipped?

    // MARK: - Initializers

    init(_ changes: [Change]) {
        for change in changes { change.note(in: &self) }
    }
}
