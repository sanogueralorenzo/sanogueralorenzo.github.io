extension BrowserEngineRegistration {
    /// Selected by the process composition, never by synced Space records.
    /// The WebKit compositions compile this file; the Chromium framework
    /// supplies its own and excludes this one.
    static var current: BrowserAdapterRegistration { webKit }
}
