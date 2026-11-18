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

struct BrowserPageContent: View {
    let page: BrowserPage
    let store: BrowserStore
    var body: some View {
        ZStack(alignment: .topTrailing) {
            BrowserWebView(
                page: page, store: store, ownerWindowID: page.hostingWindowID, revision: store.runtimeRevision,
                mirrorImage: page.mirrorImage
            ).id(page.id)
            if page.showsLoadingBackground {
                BrowserBrandTheme.canvas.allowsHitTesting(false).accessibilityHidden(true)
            }
            if let failure = page.failure {
                VStack(spacing: 14) {
                    Text(failure).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    Button("Reload") {
                        page.applyContentBlocking()
                        page.reloadAfterContentBlocking()
                    }.buttonStyle(.bordered)
                }.padding(32).frame(maxWidth: .infinity, maxHeight: .infinity).background(BrowserBrandTheme.canvas)
            }
            BrowserPageLoadingBar(indicator: page.loadingIndicator).id(page.id)
            if store.findsPage && store.selectedTab?.id == page.id {
                BrowserFindBar(page: page, store: store).padding(12)
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity).modifier(PageTranslation(page: page, store: store))
    }
}

private struct BrowserPageLoadingBar: View {
    let indicator: BrowserPage.LoadingIndicator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var width: CGFloat {
        switch indicator {
        case .hidden: 0
        case .loading: reduceMotion ? 0.25 : 0.65
        case .revealed: 1
        }
    }

    private var sweep: Animation? {
        guard !reduceMotion else { return nil }
        switch indicator {
        case .hidden: return nil
        case .loading: return .easeOut(duration: 0.7)
        case .revealed: return .easeOut(duration: 0.14)
        }
    }

    var body: some View {
        Rectangle().fill(.primary)
            .frame(height: 2)
            .animation(sweep) { content in
                content.scaleEffect(x: width, y: 1, anchor: .leading)
            }
            .animation(!reduceMotion && indicator == .revealed ? .easeOut(duration: 0.12).delay(0.08) : nil) { content in
                content.opacity(indicator == .loading ? 1 : 0)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

private struct BrowserFindBar: View {
    let page: BrowserPage
    let store: BrowserStore
    @FocusState private var focused: Bool
    var body: some View {
        HStack(spacing: 8) {
            TextField("Find in Page", text: Binding(get: { store.findText }, set: { store.findText = $0 }))
                .textFieldStyle(.plain).frame(width: 200).focused($focused).onSubmit { find(false) }
            Button {
                find(true)
            } label: {
                Image(systemName: "chevron.up")
            }
            Button {
                find(false)
            } label: {
                Image(systemName: "chevron.down")
            }
            Button {
                store.findsPage = false
            } label: {
                Image(systemName: "xmark")
            }
        }.padding(10).background(BrowserBrandTheme.surface, in: RoundedRectangle(cornerRadius: BrowserRadius.control))
            .buttonStyle(BrowserChromeButtonStyle()).onChange(of: store.findText) { find(false) }.onAppear {
                focused = true
            }.onExitCommand { store.findsPage = false }
    }
    private func find(_ backwards: Bool) {
        let configuration = WKFindConfiguration()
        configuration.backwards = backwards
        configuration.wraps = true
        page.webView.find(store.findText, configuration: configuration) { _ in }
    }
}
