/// A Peek or Quick Window that holds a transient page lease, and settles it
/// when a lease disposition says the page may not be kept.
@MainActor
protocol BrowserTransientLeaseHolder: AnyObject {
    /// Lets the page go, as it does while the request is no longer presented.
    func releaseLease()

    /// Dismisses the request, whose source is gone.
    func dismissUnavailableRequest()

    /// Lets the page go while the request's Space is locked.
    func setSourceLocked(_ isLocked: Bool)
}
