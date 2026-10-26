/// macOS resolves the shared transient-lease seam to `BrowserTransientPageLease`.
///
/// Shared code names this type so one lease bookkeeping helper compiles against
/// whichever lease its target owns.
typealias BrowserPlatformTransientPageLease = BrowserTransientPageLease
