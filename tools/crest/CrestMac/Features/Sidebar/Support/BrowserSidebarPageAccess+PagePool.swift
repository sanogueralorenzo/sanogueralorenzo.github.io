import Foundation

extension BrowserSidebarPageAccess {
    /// Binds the sidebar's page seam to the window's card pool, which also
    /// answers for a tab's sharing and the audio a row draws.
    init(pages: BrowserPagePool, browser: BrowserStore, spaceAccess: BrowserSpaceAccessController) {
        self.init(
            pages: pages, browser: browser, spaceAccess: spaceAccess,
            selectPages: { pages.selectSpace(in: browser) })
        isSharedAsTab = { assignment in
            pages.residentPage(matching: assignment)?.isSharedAsTab ?? false
        }
        isSharingTab = { assignment in
            pages.residentPage(matching: assignment)?.isSharingTab ?? false
        }
        stopTabSharing = { assignment in
            pages.residentPage(matching: assignment)?.stopTabSharing()
        }
        tabSharingCounterpartID = { assignment in
            pages.residentPage(matching: assignment).flatMap(pages.tabSharingCounterpart(of:))
        }
        audioSpectrum = { assignment in
            pages.audioSpectrum(matching: assignment)
        }
    }
}
