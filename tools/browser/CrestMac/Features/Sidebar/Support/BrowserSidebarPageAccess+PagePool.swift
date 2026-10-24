import Foundation

extension BrowserSidebarPageAccess {
    /// Binds the sidebar's page seam to the window's card pool.
    ///
    /// The pool is captured rather than read once: every closure goes back to
    /// it at call time, which is what keeps a row's residency and favicon
    /// reads inside Observation's tracking.
    init(pages: BrowserPagePool, browser: BrowserStore, spaceAccess: BrowserSpaceAccessController) {
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
            unloadPage: { tabID, assignment in
                guard let tab = browser.spaceModel(matching: assignment)?.tabs.model(tabID)
                else { return }
                if !tab.placement.isDurable {
                    pages.unloadPage(for: tabID, matching: assignment)
                } else if BrowserDurableTabCloseAction(browser: browser, spaceAccess: spaceAccess).perform(
                    BrowserTabRuntimeAssignment(
                        tabID: tabID, spaceID: assignment.spaceID, profileID: assignment.profileID
                    ))
                {
                    pages.select()
                }
            },
            pullFavicon: { tabID, assignment in
                await pages.pullFavicon(for: tabID, matching: assignment)
            },
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
            audioSpectrum: { assignment in
                pages.audioSpectrum(matching: assignment)
            }
        )
    }
}
