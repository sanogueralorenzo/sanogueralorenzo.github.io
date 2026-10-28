/// The page's document closed a notification it posted.
struct BrowserPageWebNotificationClosed: BrowserPageEngineEvent {
    // MARK: - Variables

    let notificationID: String

    // MARK: - Actions - Page

    func apply(to page: BrowserPage) {
        page.withdrawWebNotification(page.engineWebNotificationIdentifier(notificationID))
    }
}
