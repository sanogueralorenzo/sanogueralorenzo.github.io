import Dispatch
import Foundation

/// Where a tab's favicon bytes live now that the session core does not carry
/// them.
///
/// Keyed by tab rather than by content hash. A hash key would dedupe icons shared
/// by tabs on one site, but it would also have to be written into the core blob
/// for the load-time join to find it — a new stored field on the tab record and
/// its sync payload. Keying by the tab that owns the icon keeps the tab record
/// untouched: the join already knows every tab ID, and
/// "which favicons are still referenced" is exactly "which live tabs still
/// exist", so there is no reference count to keep honest.
protocol BrowserFaviconStoring: AnyObject, Sendable {
    func favicon(tabID: UUID) -> Data?
    /// Updates one live tab's last known favicon. Missing or invalid bytes leave
    /// the cached file alone; pruning is the only operation that removes it.
    func reconcile(_ faviconData: Data?, tabID: UUID)
    /// Drops favicons for tabs the live session no longer has.
    func pruneFavicons(keeping tabIDs: Set<UUID>)
    func flushPendingWrites() async
}
