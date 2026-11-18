import WebKit

/// The fork's titlebar input protection without its engine adapter or core bridge.
@MainActor
final class BrowserNativeWebView: WKWebView {
    weak var page: BrowserPage?
    var contextSelection = ""
    private var searchText = ""
    override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        super.willOpenMenu(menu, with: event)
        searchText = contextSelection
        contextSelection = ""
        func clean(_ menu: NSMenu) {
            let hidden = [
                "SpellingMenu", "ShowSpellingPanel", "CheckSpelling", "CheckSpellingWhileTyping",
                "CheckGrammarWithSpelling", "SearchWeb",
            ]
            for item in menu.items {
                if hidden.contains(where: { item.identifier?.rawValue == "WKMenuItemIdentifier" + $0 }) {
                    menu.removeItem(item)
                } else {
                    if item.identifier?.rawValue == "WKMenuItemIdentifierOpenLinkInNewWindow" {
                        item.title = "Open Link in This Space"
                    }
                    if let sub = item.submenu { clean(sub) }
                }
            }
        }
        clean(menu)
        if !searchText.isEmpty, let store = page?.owner {
            let item = NSMenuItem(
                title: "Search with " + store.preferences.searchProvider.rawValue, action: #selector(searchSelection),
                keyEquivalent: "")
            item.target = self
            menu.insertItem(item, at: 0)
        }
    }
    @objc private func searchSelection() {
        guard let store = page?.owner, let url = store.preferences.searchProvider.searchURL(searchText) else { return }
        store.open(url)
    }
    private lazy var pointer = BrowserTitleBarPointerTracker(view: self, region: .page)
    private var pointerArea: NSTrackingArea?

    var displayCaptureActive: Bool {
        let selector = NSSelectorFromString("_displayCaptureState")
        guard responds(to: selector) else { return false }
        typealias Getter = @convention(c) (AnyObject, Selector) -> Int
        return unsafeBitCast(method(for: selector), to: Getter.self)(self, selector) != 0
    }

    func stopDisplayCapture() {
        let selector = NSSelectorFromString("_setDisplayCaptureState:completionHandler:")
        guard responds(to: selector) else { return }
        typealias Action =
            @convention(c) (AnyObject, Selector, Int, @escaping @convention(block) @Sendable () -> Void) -> Void
        unsafeBitCast(method(for: selector), to: Action.self)(self, selector, 0, { @Sendable in })
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let pointerArea { removeTrackingArea(pointerArea) }
        let area = pointer.makeTrackingArea()
        pointerArea = area
        addTrackingArea(area)
        pointer.checkPointerSoon()
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow !== window { pointer.release() }
        super.viewWillMove(toWindow: newWindow)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        pointer.checkPointerSoon()
    }

    override func layout() {
        super.layout()
        pointer.checkPointerSoon()
    }
}
