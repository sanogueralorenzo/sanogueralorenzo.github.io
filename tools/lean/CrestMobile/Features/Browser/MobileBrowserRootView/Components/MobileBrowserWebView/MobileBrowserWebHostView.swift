import UIKit
import WebKit

/// Shows a page's model-owned web view where SwiftUI placed this host.
///
/// SwiftUI can hold two hosts for one page at once, and either can be the one
/// it dismantles first. During an animated replacement it keeps updating the
/// outgoing host after the incoming one claimed the web view; during a removal
/// transition the outgoing view can even build a new host for a page it only
/// now shows. The newest claim shows the web view, and when the host showing
/// it lets go, the web view returns to the newest host still asking for it, so
/// it always ends up in whichever host survives.
@MainActor
final class MobileBrowserWebHostView: UIView {
    // MARK: - Static Variables

    /// Every host that asked for a web view and has not let it go.
    private static let claimants = NSHashTable<MobileBrowserWebHostView>.weakObjects()
    /// The number of claims made so far, which orders them.
    private static var claimCount = 0

    // MARK: - Variables

    private weak var hostedWebView: WKWebView?
    private var viewport = MobileBrowserPageViewport.inline
    /// When this host claimed `hostedWebView`: the newest claim is the largest.
    private var claim = 0

    // MARK: - Actions - Hosting

    /// Claims `webView` and shows it here. Asking again for the web view this
    /// host already claimed changes nothing, even when a newer host took it
    /// meanwhile: that host shows it until it lets go.
    func attach(_ webView: WKWebView) {
        guard hostedWebView !== webView else { return }
        detach(stopsLoading: false)
        Self.claimCount &+= 1
        claim = Self.claimCount
        hostedWebView = webView
        Self.claimants.add(self)
        show(webView)
    }

    /// Lets go of the web view this host claimed. When it was showing it, the
    /// web view stops loading if `stopsLoading` asks, leaves, and moves to
    /// the newest other host that still claims it.
    func detach(stopsLoading: Bool) {
        guard let hostedWebView else { return }
        Self.claimants.remove(self)
        let showsHostedWebView = hostedWebView.superview === self
        if stopsLoading, showsHostedWebView {
            hostedWebView.stopLoading()
        }
        if showsHostedWebView {
            hostedWebView.obscuredContentInsets = .zero
            hostedWebView.setMinimumViewportInset(
                .zero,
                maximumViewportInset: .zero
            )
            hostedWebView.scrollView.contentInset = .zero
            hostedWebView.scrollView.verticalScrollIndicatorInsets = .zero
            hostedWebView.removeFromSuperview()
        }
        self.hostedWebView = nil
        guard showsHostedWebView else { return }
        Self.claimants.allObjects
            .filter { $0.hostedWebView === hostedWebView }
            .max { $0.claim < $1.claim }?
            .show(hostedWebView)
    }

    /// Puts `webView`, which this host claimed, on screen here. The web view
    /// is placed by its frame, not by constraints: for element full screen
    /// WebKit lifts it into a window of its own, which sizes it by frame and
    /// autoresizing mask, and later puts it back here by frame. Constraints
    /// would leave it no size in full screen, and none once it came back.
    private func show(_ webView: WKWebView) {
        webView.removeFromSuperview()
        webView.translatesAutoresizingMaskIntoConstraints = true
        webView.transform = .identity
        addSubview(webView)
        applyViewportInsets()
    }

    // MARK: - Actions - Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        placeHostedWebView()
    }

    /// WebKit puts the web view back here when its page leaves full screen.
    override func didAddSubview(_ subview: UIView) {
        super.didAddSubview(subview)
        guard subview === hostedWebView else { return }
        applyViewportInsets()
    }

    /// Fits the web view this host shows to the host, clear of the viewport's
    /// frame insets. It is placed by bounds and centre rather than frame, which
    /// stay true while a history swipe shifts the page aside.
    private func placeHostedWebView() {
        guard let hostedWebView, hostedWebView.superview === self else { return }
        let frame = pageFrame
        hostedWebView.bounds = CGRect(
            origin: .zero,
            size: CGSize(width: max(frame.width, 0), height: max(frame.height, 0))
        )
        hostedWebView.center = CGPoint(x: frame.midX, y: frame.midY)
    }

    /// Where the page sits in this host, clear of the viewport's frame insets
    /// and unshifted: the edges a history swipe comes in from.
    var pageFrame: CGRect {
        bounds.inset(by: viewport.webViewFrameInsets)
    }

    // MARK: - Actions - History swipe

    /// Moves the page `offset` points sideways while a history swipe follows
    /// the finger, clipping it to this host so it never slides over what sits
    /// beside it. Zero puts it back.
    func shiftPage(by offset: CGFloat) {
        guard let hostedWebView, hostedWebView.superview === self else { return }
        clipsToBounds = true
        hostedWebView.transform = CGAffineTransform(translationX: offset, y: 0)
    }

    /// Stops clipping once a history swipe has settled the page back in place.
    func endPageShift() {
        hostedWebView?.transform = .identity
        clipsToBounds = false
    }

    // MARK: - Actions - Viewport

    func configureViewport(_ viewport: MobileBrowserPageViewport) {
        guard self.viewport != viewport else { return }
        self.viewport = viewport
        applyViewportInsets()
    }

    /// The viewport is applied from the value SwiftUI hands down rather than
    /// from this view's own `safeAreaInsets`. `MobileBrowserPageViewport`
    /// carries the reasoning.
    private func applyViewportInsets() {
        guard let hostedWebView, hostedWebView.superview === self else { return }
        let overlayInsets = viewport.chromeOverlayInsets
        let viewportRange = viewport.viewportRangeInsets
        let scrollView = hostedWebView.scrollView

        // Keep the WebKit surface full-height so ordinary scrolling content
        // remains visible below Liquid Glass. The bottom-only content inset
        // extends the terminal scroll range without changing the web view's
        // frame or the viewport range WebKit reports to fixed, sticky, svh,
        // and lvh layouts.
        placeHostedWebView()
        hostedWebView.setMinimumViewportInset(
            viewportRange.minimum,
            maximumViewportInset: viewportRange.maximum
        )
        hostedWebView.obscuredContentInsets = overlayInsets
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.contentInset = overlayInsets
        scrollView.verticalScrollIndicatorInsets = overlayInsets
    }
}
