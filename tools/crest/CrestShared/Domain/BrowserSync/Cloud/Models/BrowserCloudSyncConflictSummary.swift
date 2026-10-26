struct BrowserCloudSyncConflictSummary: Equatable, Sendable {
    let localRecordCount: Int
    let cloudRecordCount: Int
    let localSpaceCount: Int
    let cloudSpaceCount: Int

}

extension BrowserCloudSyncConflictSummary {
    /// The counts the core compared this device's content and the cloud's by.
    init(_ comparison: CloudContentComparison) {
        self.init(
            localRecordCount: comparison.deviceRecords, cloudRecordCount: comparison.cloudRecords,
            localSpaceCount: comparison.deviceSpaces, cloudSpaceCount: comparison.cloudSpaces)
    }
}
