import AppKit
import SwiftUI
import WebKit

struct BrowserWebView: NSViewRepresentable {
    let page: BrowserPage
    let store: BrowserStore
    let ownerWindowID: UUID?
    let revision: Int
    let mirrorImage: NSImage?
    func makeNSView(context: Context) -> BrowserWebHost { BrowserWebHost() }
    func updateNSView(_ host: BrowserWebHost, context: Context) { host.update(page: page, store: store) }
}

@MainActor final class BrowserWebHost: NSView {
    private weak var page: BrowserPage?
    private weak var store: BrowserStore?
    private let mirror = NSImageView()
    private var capturedGeneration = -1
    override init(frame: NSRect) {
        super.init(frame: frame)
        mirror.imageScaling = .scaleProportionallyUpOrDown
    }
    required init?(coder: NSCoder) { nil }
    func update(page: BrowserPage, store: BrowserStore) {
        guard !store.isClosed, !page.isRetired else { return }
        self.page = page
        self.store = store
        if page.hostingWindowID == nil || page.hostingWindowID == store.id || window?.isKeyWindow == true {
            page.hostingWindowID = store.id
            page.owner = store
            mirror.removeFromSuperview()
            if page.webView.superview !== self {
                page.webView.removeFromSuperview()
                addSubview(page.webView)
            }
            page.webView.frame = bounds
            page.webView.autoresizingMask = [.width, .height]
            if capturedGeneration != page.documentRevision, bounds.width > 0 {
                capturedGeneration = page.documentRevision
                page.captureMirror()
            }
        } else {
            if page.webView.superview === self { page.webView.removeFromSuperview() }
            mirror.image = page.mirrorImage
            mirror.frame = bounds
            mirror.autoresizingMask = [.width, .height]
            if mirror.superview == nil { addSubview(mirror) }
        }
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let page, let store { update(page: page, store: store) }
    }
    override func mouseDown(with event: NSEvent) {
        guard let page, let store else { return }
        page.hostingWindowID = store.id
        page.owner = store
        store.runtimeRevision &+= 1
        update(page: page, store: store)
        window?.makeFirstResponder(page.webView)
    }
}
