#if DEBUG
    import Foundation

    extension CrestCore {
        /// A memory-only core that hosts pages the way the app composes one, for
        /// tests: WebKit is registered as its default engine, erasing its
        /// profiles' stores with `profileStores` and compiling its pages'
        /// content rules with `contentRuleLists`, or as the launch allows.
        static func hostingPages(
            profileStores: any BrowserEngineProfileRemoving = WebKitBrowserWebsiteDataStoreRemover(),
            contentRuleLists: (any BrowserContentRuleListProviding)? = nil
        ) -> CrestCore {
            let core = CrestCore()
            core.engines.register(
                WebKitEngineBinding(profileStores: profileStores, contentRuleLists: contentRuleLists), isDefault: true)
            return core
        }
    }
#endif
