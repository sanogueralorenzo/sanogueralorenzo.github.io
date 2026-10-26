#if DEBUG
    import Foundation

    extension TabState.Seed {
        // MARK: - Variables

        /// The address the tab shows, as the platform reads addresses.
        var address: URL? { url.flatMap(URL.init(string:)) }
    }
#endif
