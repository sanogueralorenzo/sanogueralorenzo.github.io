import Foundation

struct BrowserCloudSyncDiagnostics: Equatable, Sendable {
    let containerIdentifier: String?
    let isEnabled: Bool
    let accountState: CloudAccountState
    let phase: CloudSyncPhase
    let localRecordCount: Int
    let pendingUploadCount: Int
    let observedCloudRecordCount: Int?
    let lastAttemptAt: Date?
    let lastSuccessAt: Date?
    let lastFetchedRecordCount: Int
    let lastUploadedRecordCount: Int
    let hasError: Bool
    let requiresReconciliation: Bool
    let skippedRecordCount: Int
    let requiresAppUpdate: Bool
    let cloudDataWasRemoved: Bool

    var report: String {
        let formatter = ISO8601DateFormatter()
        let attempt = lastAttemptAt.map(formatter.string(from:)) ?? "Never"
        let success = lastSuccessAt.map(formatter.string(from:)) ?? "Never"
        return """
            Crest iCloud Sync Diagnostics
            Container: \(containerIdentifier ?? "Not configured")
            Enabled: \(isEnabled)
            Account: \(String(localized: accountState.title))
            Status: \(String(localized: phase.title))
            Local records: \(localRecordCount)
            Pending uploads: \(pendingUploadCount)
            Cloud records observed: \(observedCloudRecordCount.map(String.init) ?? "Unknown")
            Last attempt: \(attempt)
            Last success: \(success)
            Last download batch: \(lastFetchedRecordCount)
            Last upload batch: \(lastUploadedRecordCount)
            Error present: \(hasError)
            Reconciliation required: \(requiresReconciliation)
            Records skipped: \(skippedRecordCount)
            Needs app update: \(requiresAppUpdate)
            iCloud data removed: \(cloudDataWasRemoved)
            """
    }
}
