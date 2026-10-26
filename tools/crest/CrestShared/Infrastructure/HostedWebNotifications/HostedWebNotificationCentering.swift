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

extension BrowserHostedWebNotificationCentering {
    /// Shows `delivery` through the system, its title and body cut to what a
    /// notification holds, while `isCurrent` holds: the system must let Crest
    /// show notifications, and one that stops being current while the system
    /// answers is taken down again. `eventHandler` hears a click. Answers
    /// whether it shows.
    func show(
        _ delivery: BrowserHostedWebNotificationDelivery,
        while isCurrent: @MainActor () -> Bool,
        eventHandler: @escaping @MainActor (BrowserHostedWebNotificationEvent) -> Void
    ) async -> Bool {
        guard isCurrent(), await currentAuthorization() == .authorized, isCurrent() else { return false }
        let shown = BrowserHostedWebNotificationDelivery(
            identifier: delivery.identifier, title: String(delivery.title.prefix(200)),
            body: String(delivery.body.prefix(1_000)), origin: delivery.origin, isSilent: delivery.isSilent)
        do {
            try await add(shown, eventHandler: eventHandler)
        } catch {
            return false
        }
        guard isCurrent() else {
            await remove(identifier: delivery.identifier)
            return false
        }
        return true
    }
}
