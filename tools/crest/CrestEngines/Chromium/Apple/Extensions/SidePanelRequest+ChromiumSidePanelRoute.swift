#if CREST_CHROMIUM_HOST
    import Foundation

    extension SidePanelRequest {
        /// Takes the request through `route`, as the request asks.
        @MainActor func take(through route: ChromiumSidePanelRoute) {
            switch self {
            case .open: route.open()
            case .close: route.close()
            case .toggle: route.toggle()
            }
        }
    }
#endif
