/// Holds a transient lease weakly so the page store's bookkeeping never keeps a
/// dismissed transient overlay alive past the moment it lets go.
final class WeakBrowserTransientPageLease {
    weak var value: BrowserPlatformTransientPageLease?

    init(_ value: BrowserPlatformTransientPageLease) {
        self.value = value
    }
}
