protocol BrowserCloudSyncRemoteService: Sendable {
    func hasRequiredEntitlement() async -> Bool
    func accountState() async throws -> CloudAccountState
    func loadSnapshot() async throws -> [SyncRecord]
    nonisolated func message(for error: any Error) -> String
}
