import Foundation

extension BrowserSidebarPreviewFixture {
    /// An empty, ephemeral card pool for the windowed shell's own previews.
    ///
    /// The shared fixture stops at the sidebar's ports; the windowed sidebar
    /// still hands its page body a real pool, because the address band and the
    /// pinned extension seam read it directly. Nothing is loaded into it, and
    /// the data stores are ephemeral, so no preview leaves anything behind.
    @MainActor
    static func makePages(for browser: BrowserStore) -> BrowserPagePool {
        BrowserPagePool(
            browser: browser,
            browsingMode: .privateBrowsing,
            usesEphemeralWebsiteDataStores: true
        )
    }
}
