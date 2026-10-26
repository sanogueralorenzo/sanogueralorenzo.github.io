/// A document in the page posted a notification through an engine that
/// hosts the Notifications API itself.
struct BrowserPageWebNotificationPosted: BrowserPageEngineEvent {
    // MARK: - Variables

    let posted: WebNotificationPosted

    // MARK: - Actions - Page

    func apply(to page: BrowserPage) {
        page.showEngineWebNotification(posted)
    }
}
