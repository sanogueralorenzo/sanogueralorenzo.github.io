#if CREST_CHROMIUM_HOST
    import SwiftUI

    /// Chromium contributes its own privileged flags page to Crest Settings.
    /// The page stays inside the Settings detail area and belongs to the
    /// Settings tab's Space; no shared settings view knows how Chromium
    /// renders it.
    struct BrowserChromiumFeatureFlagSettingsPane: View {
        /// The Settings tab's Space, or nil while it is locked.
        let space: SpaceModel?
        /// The window that shows Settings.
        let browser: BrowserStore

        var body: some View {
            if let space {
                ChromiumFeatureFlagsSurface(space: space, browser: browser)
                    .id(BrowserSpaceRuntimeAssignment(space: space))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView(
                    "Feature Flags Unavailable",
                    systemImage: "flag.slash",
                    description: Text("Open Settings from an unlocked Space to view Chromium flags.")
                )
            }
        }
    }

    private struct ChromiumFeatureFlagsSurface: NSViewRepresentable {
        let space: SpaceModel
        let browser: BrowserStore

        func makeCoordinator() -> Coordinator { Coordinator(space: space, browser: browser) }

        func makeNSView(context: Context) -> ChromiumNativePageView {
            context.coordinator.native?.surface ?? ChromiumNativePageView()
        }

        func updateNSView(_ view: ChromiumNativePageView, context: Context) {}

        static func dismantleNSView(_ view: ChromiumNativePageView, coordinator: Coordinator) {
            coordinator.close()
        }

        /// The flags page is one of Chromium's own pages that Settings shows.
        /// The core opens it, like every page, for the Settings tab's Space in
        /// this window, owned by no tab, and loads it; closing the pane
        /// releases it.
        @MainActor
        final class Coordinator {
            private let page: CorePage?
            let native: ChromiumNativePage?

            init(space: SpaceModel, browser: BrowserStore) {
                let core = browser.core
                let opened = core.engines.open(
                    OpenPage(
                        pageID: UUID(), workspaceID: browser.family.workspaceID, spaceID: space.id, tabID: nil,
                        windowID: browser.windowID, transient: .settings, openerPageID: nil))
                page = opened?.page
                native = (opened?.built as? ChromiumPageAdapter)?.native
                native?.profileID = space.profileID
                native?.isPrivateBrowsing = browser.isPrivateBrowsing
                guard let page else { return }
                _ = try? core.send(Navigate(pageID: page.id, input: "crest://flags/"))
            }

            func close() {
                native?.dispose()
                page?.release(keepingState: false)
            }
        }
    }
#endif
