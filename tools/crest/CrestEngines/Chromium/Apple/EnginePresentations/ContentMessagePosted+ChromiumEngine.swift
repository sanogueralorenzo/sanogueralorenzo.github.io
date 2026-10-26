#if CREST_CHROMIUM_HOST
    import Foundation

    extension ContentMessagePosted {
        @MainActor func present(on engine: ChromiumEngine) {
            // The body is whatever the bridge posted, so it stays an opaque value.
            guard let page = engine.presentedPage(pageID), let receive = page.contentReceivers[handler],
                let value = try? JSONSerialization.jsonObject(with: Data(body.utf8), options: .fragmentsAllowed)
            else { return }
            receive(
                BrowserContentMessage(
                    handlerName: handler, body: value,
                    frame: BrowserContentFrame(
                        isMainFrame: frame.isMainFrame, securityProtocol: frame.protocol, host: frame.host,
                        port: Int(frame.port), handle: frame.id as NSString)))
        }
    }
#endif
