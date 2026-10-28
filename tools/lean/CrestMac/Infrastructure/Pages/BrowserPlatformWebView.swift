import SwiftUI

extension EnvironmentValues {
    @Entry var browserPagePresentationWindowID: UUID? = nil
    /// How the window shows the Space this page is drawn in.
    @Entry var browserPagePresentation = BrowserPagePresentation.presented
    @Entry var browserWebFocusRestorationGate =
        BrowserWebFocusRestorationGate.suppressed
}

struct BrowserPlatformWebView: NSViewRepresentable {
    @Environment(\.browserPagePresentationWindowID) private var presentationWindowID
    @Environment(\.browserPagePresentation) private var presentation
    let page: BrowserPage
    let isPageActive: Bool
    let focusRestorationGate: BrowserWebFocusRestorationGate

    func makeNSView(context: Context) -> BrowserWebHostView {
        let host = BrowserWebHostView()
        host.updatePresentation(presentation)
        host.attach(
            page.nativeView,
            focusRestoration: page.focusRestoration,
            allowsAttachment: allowsAttachment
        )
        host.updateFocusPresentation(
            isPageActive: isPageActive,
            gate: focusRestorationGate
        )
        return host
    }

    func updateNSView(_ host: BrowserWebHostView, context: Context) {
        host.attach(
            page.nativeView,
            focusRestoration: page.focusRestoration,
            allowsAttachment: allowsAttachment
        )
        host.updateFocusPresentation(
            isPageActive: isPageActive,
            gate: focusRestorationGate
        )
        // After the attachment, so a page that arrives with its Space comes
        // on screen once, and with the focus the update just settled.
        host.updatePresentation(presentation)
    }

    static func dismantleNSView(_ host: BrowserWebHostView, coordinator: Void) {
        host.detach()
    }

    private var allowsAttachment: Bool {
        guard let presentationWindowID, let owner = page.windowRouting?.pool else { return true }
        return owner.windowID == presentationWindowID
    }
}
