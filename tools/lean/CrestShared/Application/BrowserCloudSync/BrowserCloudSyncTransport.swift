protocol BrowserCloudSyncTransport: Sendable {
    func start() async
    func stop() async
    func syncNow() async throws
    func pullFromICloud() async throws -> Int
    func notifyLocalChanges() async
}
