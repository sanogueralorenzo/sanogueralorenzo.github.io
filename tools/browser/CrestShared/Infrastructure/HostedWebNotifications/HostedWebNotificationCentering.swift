@MainActor
protocol BrowserHostedWebNotificationCentering: AnyObject {
    func currentAuthorization() async -> BrowserSystemAuthorization
    func requestAuthorization() async -> BrowserSystemAuthorization
    func add(
        _ delivery: BrowserHostedWebNotificationDelivery,
        eventHandler: @escaping @MainActor (BrowserHostedWebNotificationEvent) -> Void
    ) async throws
    func remove(identifier: String) async
}
