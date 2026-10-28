import SwiftUI
import UIKit

struct MobileBrowserWebView: UIViewRepresentable {
    let page: MobileBrowserPage
    var viewport = MobileBrowserPageViewport.inline
    /// Observes page taps without taking them away from WebKit.
    var handleInteraction: (() -> Void)?
    /// An unfocused split card's request to become the focused one.
    ///
    /// A SwiftUI `TapGesture` over web content is unreliable — the page's own
    /// gesture recognizers reach the touch first — so the recognizer is installed
    /// on the host beside the address-focus one, with `cancelsTouchesInView`
    /// false so the page still receives the tap it was given. `nil` outside a
    /// split, where there is no second card to focus.
    var requestFocus: (() -> Void)?
    /// Keeps the page out of VoiceOver's reach, as for a page waiting out of
    /// sight for the address bar's swipe. WebKit's content answers VoiceOver
    /// itself, so SwiftUI's own hiding does not reach it.
    var hidesFromAccessibility = false

    func makeCoordinator() -> MobileBrowserWebViewCoordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> MobileBrowserWebHostView {
        let host = MobileBrowserWebHostView()
        host.configureViewport(viewport)
        host.attach(page.webView)
        hideFromAccessibility(host)
        if context.coordinator.dismissFocusRecognizer.view == nil {
            host.addGestureRecognizer(
                context.coordinator.dismissFocusRecognizer
            )
        }
        context.coordinator.handleInteraction = handleInteraction
        context.coordinator.historySwipe.install(on: host)
        context.coordinator.historySwipe.page = page
        page.historySwipe = context.coordinator.historySwipe
        installFocusRecognizerIfNeeded(on: host, coordinator: context.coordinator)
        return host
    }

    func updateUIView(_ host: MobileBrowserWebHostView, context: Context) {
        host.configureViewport(viewport)
        host.attach(page.webView)
        hideFromAccessibility(host)
        context.coordinator.handleInteraction = handleInteraction
        context.coordinator.historySwipe.page = page
        page.historySwipe = context.coordinator.historySwipe
        installFocusRecognizerIfNeeded(on: host, coordinator: context.coordinator)
    }

    /// Hides the page from VoiceOver, or shows it again, on the host and the
    /// web view both: the web view moves between hosts as a swipe lands, and
    /// WebKit's content answers VoiceOver through it, not through the host.
    private func hideFromAccessibility(_ host: MobileBrowserWebHostView) {
        host.accessibilityElementsHidden = hidesFromAccessibility
        page.webView.accessibilityElementsHidden = hidesFromAccessibility
    }

    private func installFocusRecognizerIfNeeded(
        on host: MobileBrowserWebHostView,
        coordinator: MobileBrowserWebViewCoordinator
    ) {
        coordinator.requestFocus = requestFocus
        guard requestFocus != nil,
            coordinator.cardFocusRecognizer.view == nil
        else { return }
        host.addGestureRecognizer(coordinator.cardFocusRecognizer)
    }

    static func dismantleUIView(
        _ host: MobileBrowserWebHostView,
        coordinator: MobileBrowserWebViewCoordinator
    ) {
        // The retained page model owns navigation. SwiftUI can dismantle and
        // recreate this transient host while a start-page navigation is being
        // handed off, so tearing the host down must not cancel the load.
        host.detach(stopsLoading: false)
    }
}
