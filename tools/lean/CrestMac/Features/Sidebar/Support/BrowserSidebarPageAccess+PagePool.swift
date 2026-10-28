import Foundation

extension BrowserSidebarPageAccess {
    /// Binds the sidebar's page seam to the window's card pool.
    ///
    /// The pool is captured rather than read once: every closure goes back to
    /// it at call time, which is what keeps a row's residency and favicon
    /// reads inside Observation's tracking.
    init(pages: BrowserPagePool, browser: BrowserStore) {
        self.init(
            containsResidentPage: { tabID in
                pages.containsResidentPage(for: tabID) || pages.nativeTabs.tabIDs.contains(tabID)
            },
            containsResidentPageMatching: { assignment in
                pages.containsResidentPage(matching: assignment) || pages.nativeTabs.contains(assignment)
            },
            siteThemeIconAccent: { assignment in
                pages.siteThemeIconAccent(matching: assignment)
            },
            residencyRevision: { pages.residencyRevision &+ pages.nativeTabs.residencyRevision },
            selectPages: { pages.selectSpace(in: browser) },
            deactivatePagePresentation: { pages.deactivatePagePresentation() },
            downloadCenter: pages.downloadCenter,
            isSharedAsTab: { assignment in
                pages.residentPage(matching: assignment)?.isSharedAsTab ?? false
            },
            isSharingTab: { assignment in
                pages.residentPage(matching: assignment)?.isSharingTab ?? false
            },
            stopTabSharing: { assignment in
                pages.residentPage(matching: assignment)?.stopTabSharing()
            },
            tabSharingCounterpartID: { assignment in
                pages.residentPage(matching: assignment).flatMap(pages.tabSharingCounterpart(of:))
            },
            mediaSession: { assignment in
                pages.mediaSession(matching: assignment)
            },
            setMuted: { muted, assignment in
                pages.setMuted(muted, matching: assignment)
            },
            liveState: { assignment in
                pages.residentPage(matching: assignment)?.live
            }
        )
    }
}
