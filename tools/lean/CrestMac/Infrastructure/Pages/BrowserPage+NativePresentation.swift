import AppKit

/// Native presentation operations used by Crest's existing views. Engine
/// objects and snapshot configuration stay behind the page boundary.
extension BrowserPage {
    var nativeView: NSView { pageEngine.nativeView }
    var presentationWindow: NSWindow? { nativeView.window }
    var viewportSize: CGSize { nativeView.bounds.size }

    var canReviewCertificate: Bool {
        Self.canReviewCertificate(of: live.displayURL, hasServerTrust: serverTrust != nil)
    }

    /// A certificate is offered for review only for an HTTPS document whose
    /// server trust the engine reports.
    nonisolated static func canReviewCertificate(of url: URL?, hasServerTrust: Bool) -> Bool {
        url?.scheme?.lowercased() == "https" && hasServerTrust
    }

    /// The trust the page's current document was verified with.
    private var serverTrust: SecTrust? {
        enginePage.serverTrust(host: pageEngine.currentURL?.host())
    }

    /// Capture the certificate and its window before dismissing a popover.
    /// A later navigation must not change which certificate the action reviews.
    func certificateReviewAction() -> (@MainActor () -> Void)? {
        guard let trust = serverTrust else { return nil }
        let window = presentationWindow
        return { BrowserSiteCertificatePresenter.present(trust: trust, for: window) }
    }

    func reviewCertificate() { certificateReviewAction()?() }

    /// Issue synchronously so drag pickup can request the current frame before
    /// changing its presentation. A missing image never reveals another page.
    func captureViewport(
        width: CGFloat? = nil,
        completion: @escaping @MainActor (NSImage?) -> Void
    ) {
        enginePage.capture(width: width) { completion($0.flatMap(NSImage.init(data:))) }
    }
}
