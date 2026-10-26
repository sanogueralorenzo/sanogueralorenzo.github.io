#if DEBUG
    import Foundation

    extension BrowserStore {
        /// A window that hosts pages the way the app composes one, for tests: a
        /// family the core opens from `seed`, whose tabs wear `images`, on a
        /// core that hosts pages, and a window open over it that shows
        /// `spaceID` and `tabs` as `init(seed:images:showing:tabs:)` does. A
        /// page pool or store over this window opens every page through that
        /// core, so a page can only live in one of the session's Spaces. Pass
        /// `core` to put another workspace on a core that already hosts one, as
        /// private and temporary windows share the app's core.
        static func hostingPages(
            _ seed: SessionState.Seed = .preview,
            images: [UUID: Data] = [:],
            showing spaceID: UUID? = nil,
            tabs: [UUID: UUID] = [:],
            browsingMode: BrowserBrowsingMode = .standard,
            core: CrestCore = .hostingPages()
        ) -> BrowserStore {
            BrowserStore(
                seed: seed, images: images, showing: spaceID, tabs: tabs, browsingMode: browsingMode, core: core)
        }

        /// Tab `tabID` of Space `spaceID` as its page takes it, for a test that
        /// builds a page itself.
        func pageTab(_ tabID: UUID, in spaceID: UUID) -> BrowserPageTab {
            guard let tab = spaceModel(spaceID)?.tabs.model(tabID) else {
                preconditionFailure("A test built a page for a tab its window does not hold.")
            }
            return BrowserPageTab(tab, images: core.state.favicons)
        }

        /// Space `spaceID` of this window's workspace, for a test that builds a
        /// page itself.
        func hostedSpace(_ spaceID: UUID) -> SpaceModel {
            guard let space = spaceModel(spaceID) else {
                preconditionFailure("A test built a page for a Space its window does not hold.")
            }
            return space
        }

        /// Opens a page through the core for `tabID` in `spaceID`, and answers
        /// it with the page WebKit built, for a test that hosts the page
        /// itself. Nil when a rule refuses it.
        func openWebKitPage(in spaceID: UUID, for tabID: UUID?) -> (core: CorePage, webKit: WebKitEnginePage)? {
            guard let opened = openPage(in: spaceID, for: tabID) else { return nil }
            guard let page = opened.built as? WebKitEnginePage else {
                preconditionFailure("A test opened a page on an engine other than WebKit.")
            }
            return (opened.page, page)
        }
    }
#endif
