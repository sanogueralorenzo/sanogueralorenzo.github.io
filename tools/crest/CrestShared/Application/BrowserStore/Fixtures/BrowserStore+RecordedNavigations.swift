#if DEBUG
    import Foundation

    extension BrowserStore {
        /// Records a visit to `url` in `spaceID`, the Space this window shows
        /// unless named, as the core records one when a page finishes loading,
        /// for tests that need history without a page. The core must host
        /// pages, as `CrestCore.hostingPages()` does.
        func seedVisit(to url: URL, titled title: String, in spaceID: UUID? = nil) {
            guard let page = openReportingPage(for: nil, in: spaceID) else {
                preconditionFailure("A test recorded a visit on a core that hosts no pages.")
            }
            finishNavigation(of: page, to: url, titled: title)
            page.release(keepingState: false)
        }

        /// Opens a page through the core for `tabID` in `spaceID`, or for a
        /// Quick Window or Peek request when `tabID` is nil, on a core whose
        /// default engine is WebKit. The page loads nothing: a test reports
        /// what its engine would see with `finishNavigation(of:to:titled:icon:)`.
        func openReportingPage(for tabID: UUID?, in spaceID: UUID? = nil) -> CorePage? {
            openPage(in: spaceID ?? selectedSpaceID, for: tabID)?.page
        }

        /// Reports that `page` loaded a new document at `url`, found `icon`
        /// for it and finished titled `title`, showing it all the while, then
        /// applies what the core recorded.
        func finishNavigation(of page: CorePage, to url: URL, titled title: String, icon: Data? = nil) {
            page.report(NavigationStarted(pageID: page.id, url: url.absoluteString, sameDocument: false))
            page.report(NavigationCommitted(pageID: page.id, url: url.absoluteString, sameDocument: false))
            page.report(
                PageStateChanged(
                    pageID: page.id,
                    snapshot: PageSnapshot(
                        url: url.absoluteString, pendingURL: nil, title: title, isLoading: false,
                        security: url.scheme == "https" ? .secure : .insecure, media: [])))
            if let icon {
                page.report(PageIconChanged(pageID: page.id, url: url.absoluteString, accent: nil), icon: icon)
            }
            page.report(NavigationFinished(pageID: page.id, url: url.absoluteString, title: title))
            core.drain()
        }
    }
#endif
