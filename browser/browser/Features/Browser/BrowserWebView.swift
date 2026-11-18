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
    private struct Motion {
        private static let rampDuration: TimeInterval = 8
        private static let sweepDuration: TimeInterval = 0.14
        private static let fadeDelay: TimeInterval = 0.08
        private static let fadeDuration: TimeInterval = 0.12

        let width: Double
        let opacity: Double

        init(_ phase: BrowserPage.LoadingIndicator, at time: TimeInterval) {
            switch phase {
            case .hidden:
                width = 0
                opacity = 0
            case .loading(let startedAt):
                width = Self.estimate(after: max(0, time - startedAt))
                opacity = 1
            case .revealed(let startedAt, let revealedAt):
                let elapsed = max(0, time - revealedAt)
                let estimate = Self.estimate(after: revealedAt - startedAt)
                let completion = UnitCurve.easeOut.value(at: min(1, elapsed / Self.sweepDuration))
                let fade = min(1, max(0, (elapsed - Self.fadeDelay) / Self.fadeDuration))
                width = estimate + (1 - estimate) * completion
                opacity = 1 - UnitCurve.easeOut.value(at: fade)
            }
        }

        static func end(of phase: BrowserPage.LoadingIndicator) -> TimeInterval {
            switch phase {
            case .hidden: 0
            case .loading(let startedAt): startedAt + rampDuration
            case .revealed(_, let revealedAt): revealedAt + fadeDelay + fadeDuration
            }
        }

        private static func estimate(after elapsed: TimeInterval) -> Double {
            min(0.99, 1 - 0.72 * exp(-3.9 * elapsed) - 0.28 * exp(-0.42 * elapsed))
        }
    }

    let indicator: BrowserPage.LoadingIndicator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animatedIndicator = BrowserPage.LoadingIndicator.hidden

    private var reducedMotionWidth: Double {
        if case .loading = indicator { return 0.25 }
        return 0
    }

    var body: some View {
        let staticWidth = reduceMotion ? reducedMotionWidth : nil
        let phase = animatedIndicator
        Rectangle().fill(.primary)
            .frame(height: 2)
            .keyframeAnimator(initialValue: ProcessInfo.processInfo.systemUptime, trigger: phase) { content, time in
                let motion = Motion(phase, at: time)
                content.scaleEffect(x: staticWidth ?? motion.width, y: 1, anchor: .leading)
                    .opacity(staticWidth == nil ? motion.opacity : 1)
            } keyframes: { _ in
                let now = ProcessInfo.processInfo.systemUptime
                let end = Motion.end(of: phase)
                KeyframeTrack {
                    if end > now {
                        MoveKeyframe(now)
                        LinearKeyframe(end, duration: end - now)
                    } else {
                        MoveKeyframe(now)
                    }
                }
            }
            .onChange(of: reduceMotion ? .hidden : indicator, initial: true) { _, phase in
                animatedIndicator = phase
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
