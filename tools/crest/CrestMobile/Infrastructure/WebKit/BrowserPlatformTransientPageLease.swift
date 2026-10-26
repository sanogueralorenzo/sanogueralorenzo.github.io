/// Mobile resolves the shared transient-lease seam to
/// `MobileBrowserTransientPageLease`.
///
/// Shared code names this type so one lease bookkeeping helper compiles against
/// whichever lease its target owns.
typealias BrowserPlatformTransientPageLease = MobileBrowserTransientPageLease
