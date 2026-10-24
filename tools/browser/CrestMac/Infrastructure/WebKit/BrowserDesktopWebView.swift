import AppKit
import WebKit

@MainActor
final class BrowserDesktopWebView: WKWebView {
    /// The page that owns this view. Weak because the page owns it.
    weak var menuHost: (any BrowserDesktopWebViewMenuHost)?
    /// The page-owned record of this view's public AppKit editing responder.
    weak var focusRestoration: BrowserWebFocusRestorationController?
    weak var linkHover: BrowserLinkHoverController?
    weak var linkDrag: BrowserLinkDragController?

    override func mouseDown(with event: NSEvent) {
        linkDrag?.mouseDown(event)
        super.mouseDown(with: event)
    }

    override func viewWillMove(toSuperview newSuperview: NSView?) {
        if superview !== newSuperview {
            linkHover?.detach()
            linkDrag?.detach()
        }
        super.viewWillMove(toSuperview: newSuperview)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            linkHover?.invalidate()
            linkDrag?.detach()
        }
    }

    override func becomeFirstResponder() -> Bool {
        guard focusRestoration?.allowsNativeFocusAcquisition != false else {
            return false
        }
        let becameFirstResponder = super.becomeFirstResponder()
        if becameFirstResponder {
            focusRestoration?.remember(self)
        }
        return becameFirstResponder
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    /// Adds Crest's actions ahead of WebKit's native and extension items.
    override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        super.willOpenMenu(menu, with: event)
        if menuHost?.opensLinksInCurrentSpace == true {
            menu.relabelWebKitLinkDestination()
        }
        menu.removeWebKitSelectionSearch()
        guard let menuHost, let context = menuHost.takeMenuContext() else { return }
        BrowserPageContextMenu(
            actions: menuHost.contextMenuActions(linkURL: context.linkURL, selectionText: context.selectionText),
            host: menuHost, view: self
        ).insert(into: menu)
        if context.isEditable, let paste = menu.webKitPasteItem {
            let item = NSMenuItem(
                title: String(localized: "Paste and Match Style"), action: #selector(pasteAsPlainTextFromMenu(_:)),
                keyEquivalent: "")
            item.target = self
            item.isEnabled = paste.isEnabled
            menu.insertItem(item, at: menu.index(of: paste) + 1)
        }
        if let imageDownloadURL = context.imageDownloadURL,
            let item = menu.webKitDownloadImageItem
        {
            item.target = self
            item.action = #selector(downloadImage(_:))
            item.representedObject = imageDownloadURL
        }
    }

    /// A capture belongs to one menu. Whatever this one did not use is dropped
    /// here, so the next right-click starts from nothing even if its own report
    /// never arrives.
    override func didCloseMenu(_ menu: NSMenu, with event: NSEvent?) {
        super.didCloseMenu(menu, with: event)
        menuHost?.discardSplitViewLinkCapture()
    }

    /// Named apart from `pasteAsPlainText:` so WebKit's own handler is the one
    /// the paste reaches.
    @objc private func pasteAsPlainTextFromMenu(_ sender: NSMenuItem) {
        BrowserPlainTextPaste(for: self)?.perform()
    }

    @objc private func downloadImage(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        menuHost?.downloadImage(from: url)
    }
}

// WebKit's hover observer remains with its adapter. Other native engine views
// use the same host without inheriting WebKit-specific presentation work.
extension BrowserDesktopWebView: BrowserNativePageSurfaceLifecycle {
    func didAttach(to host: BrowserWebHostView) { linkHover?.attach(to: host) }
    func willDetach(from host: BrowserWebHostView) { linkHover?.detach(from: host) }
}
