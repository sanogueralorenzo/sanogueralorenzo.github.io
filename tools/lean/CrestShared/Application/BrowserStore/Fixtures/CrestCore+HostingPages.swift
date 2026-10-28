#if DEBUG
    import Foundation

    extension CrestCore {
        /// A memory-only core that hosts pages the way the app composes one, for
        /// tests: WebKit is registered as its default engine, erasing its
        /// profiles' stores with `profileStores` and hosting the bundled blocker
        /// through `contentBlocking`.
        static func hostingPages(
            profileStores: any BrowserEngineProfileRemoving = WebKitBrowserWebsiteDataStoreRemover(),
            contentBlocking: WebKitContentBlocking = WebKitContentBlocking()
        ) -> CrestCore {
            let core = CrestCore()
            core.engines.register(
                WebKitEngineBinding(profileStores: profileStores, contentBlocking: contentBlocking))
            return core
        }
    }
#endif
