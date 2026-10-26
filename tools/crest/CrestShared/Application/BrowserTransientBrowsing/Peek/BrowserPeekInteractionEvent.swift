/// A step of a link pull that a platform's gesture reports. Each event says
/// what it does to the Peeks the coordinator presents, so the coordinator's
/// dispatcher is `event.apply(to: self)`.
protocol BrowserPeekInteractionEvent: Sendable {
    @MainActor
    func apply(to coordinator: BrowserTransientBrowsingCoordinator)
}
