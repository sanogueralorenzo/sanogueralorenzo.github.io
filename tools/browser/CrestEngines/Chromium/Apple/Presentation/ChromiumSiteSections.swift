#if CREST_CHROMIUM_HOST
    import SwiftUI

    // The Chromium composition of the engine-contributed site sections. The names
    // and signatures match the WebKit file in CrestMac; only one of the two is ever
    // compiled into a target, so the shared presentation layer composes these
    // without naming an engine or asking a compile-time condition of its own.

    /// Crest's per-Space record decides site permissions on this engine too. Each
    /// open page's `BrowserPageSitePermissionSession` applies a change to the engine
    /// at once rather than on the next page load.
    struct BrowserEngineSitePermissionsSection: View {
        let page: BrowserPage
        let origin: SiteOrigin
        let permissionCenter: BrowserSitePermissionCenter
        @Binding var isExpanded: Bool

        var body: some View {
            BrowserSitePermissionDisclosure(
                origin: origin,
                spaceID: page.spaceID,
                permissionCenter: permissionCenter,
                isExpanded: $isExpanded
            )
        }
    }

    /// Per-site extension actions and access, alongside Crest's own site controls.
    struct BrowserEngineSiteControlsSection: View {
        let page: BrowserPage
        /// The page's Space in the read model.
        let space: SpaceModel
        let url: URL?
        let dismiss: () -> Void

        var body: some View {
            if let native = page.chromiumPage {
                ChromiumExtensionControls(
                    page: native, space: space, url: url, dismiss: dismiss)
            }
        }
    }

    /// The pinned extension actions that sit above a Space's tab list.
    struct BrowserEngineSidebarAccessory: View {
        /// The Space whose row this is, in the read model.
        let space: SpaceModel
        /// The window's own store. Extension ownership is decided against the store
        /// family that owns this window rather than against one global Space list.
        let browser: BrowserStore
        let pages: BrowserPagePool

        var body: some View {
            if browser.core.state.defaultEngineSupports(.extensions) || pinnedActionPage != nil {
                BrowserPinnedExtensionStrip(
                    page: pinnedActionPage, space: space, browser: browser)
            }
        }

        private var pinnedActionPage: ChromiumNativePage? {
            guard let tabID = browser.selectedTabID(in: space.id) else { return nil }
            return pages.activePage(
                matching: BrowserTabRuntimeAssignment(
                    tabID: tabID, spaceID: space.id, profileID: space.profileID)
            )?.chromiumPage
        }
    }

    /// The Extensions settings destination, composed by the engine that has them.
    struct BrowserEngineExtensionSettingsPane: View {
        let browser: BrowserStore
        let spaceAccess: BrowserSpaceAccessController
        /// The one Space whose extensions the pane shows, or nil to pick one.
        var spaceID: UUID?

        var body: some View {
            BrowserExtensionSettingsPane(browser: browser, spaceAccess: spaceAccess, fixedSpaceID: spaceID)
        }
    }
#endif
