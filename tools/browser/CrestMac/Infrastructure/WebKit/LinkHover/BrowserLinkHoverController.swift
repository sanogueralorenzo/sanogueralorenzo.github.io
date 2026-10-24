import AppKit
import Observation
import WebKit

/// One transient preview per page. Neither the script handler nor event monitor
/// owns the page, and only published text invalidates the SwiftUI overlay.
@Observable
@MainActor
final class BrowserLinkHoverController {
    private(set) var destination: BrowserLinkHoverDestination?
    private(set) var isExpanded = false
    /// The engine's page view; the preview only shows while the pointer is
    /// over it. WebKit pages also validate each report against the document.
    @ObservationIgnored private weak var contentView: NSView?
    @ObservationIgnored private weak var webView: WKWebView?
    @ObservationIgnored private var engineSequence = 0
    @ObservationIgnored private weak var presentationHost: NSView?
    @ObservationIgnored private var state = BrowserLinkHoverState()
    @ObservationIgnored private var work: Task<Void, Never>?
    @ObservationIgnored private var eventMonitor: Any?
    @ObservationIgnored private var windowObserver: NSObjectProtocol?
    @ObservationIgnored private var isNavigating = false
    @ObservationIgnored private var retireSource: (() -> Void)?

    init(webView: WKWebView) {
        self.webView = webView
        contentView = webView
    }

    /// An engine that reports hovered links itself.
    init(contentView: NSView) {
        self.contentView = contentView
    }

    isolated deinit {
        work?.cancel()
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
        if let windowObserver { NotificationCenter.default.removeObserver(windowObserver) }
    }

    func attach(to host: NSView) {
        guard presentationHost !== host else { return }
        detach()
        presentationHost = host
        eventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [
                .mouseMoved, .leftMouseDown, .rightMouseDown, .otherMouseDown,
                .leftMouseDragged, .rightMouseDragged, .otherMouseDragged, .scrollWheel, .keyDown,
            ]
        ) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self else { return }
                if event.type != .mouseMoved || !self.canPresent {
                    self.invalidate()
                }
            }
            return event
        }
        windowObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.invalidate() }
        }
    }

    func detach(from host: NSView? = nil) {
        if let host, presentationHost !== host { return }
        invalidate()
        presentationHost = nil
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
        eventMonitor = nil
        if let windowObserver { NotificationCenter.default.removeObserver(windowObserver) }
        windowObserver = nil
    }

    func beginNavigation() {
        isNavigating = true
        invalidate()
    }

    func didCommitNavigation() {
        isNavigating = false
        invalidate()
    }

    func didFailNavigation() {
        isNavigating = false
        invalidate()
    }

    func invalidate() {
        retireSource?()
        retireSource = nil
        work?.cancel()
        work = nil
        state.invalidate()
        publish()
    }

    func receive(_ message: WKScriptMessage) {
        guard message.webView === webView,
            message.name == BrowserLinkHoverContentBridge.name,
            let report = BrowserLinkHoverMessage(body: message.body)
        else { return }
        let document = report.document
        let sequence = report.sequence
        guard let href = report.href else {
            let previousTicket = state.ticket
            state.leave(document: document, sequence: sequence)
            if previousTicket != state.ticket {
                work?.cancel()
                work = nil
                retireSource = nil
            }
            publish()
            return
        }
        guard canPresent, BrowserLinkHoverDestination(resolvedURL: href) != nil else {
            invalidate()
            return
        }
        work?.cancel()
        let ticket = state.receive(
            document: document, sequence: sequence, href: href,
            at: ProcessInfo.processInfo.systemUptime
        )
        publish()
        let frame = message.frameInfo
        retireSource = { [weak webView] in
            webView?.callAsyncJavaScript(
                "globalThis.__crestLinkHover?.retire(documentID, sequence);",
                arguments: ["documentID": document, "sequence": sequence],
                in: frame, in: BrowserLinkHoverContentBridge.world,
                completionHandler: nil
            )
        }
        work = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(BrowserLinkHoverState.appearanceDelay))
                guard let self, !Task.isCancelled, self.state.ticket == ticket else { return }
                let valid = await self.validate(document: document, sequence: sequence, href: href, frame: frame)
                guard !Task.isCancelled, self.state.ticket == ticket else { return }
                guard valid, self.canPresent,
                    self.state.reveal(ticket: ticket, at: ProcessInfo.processInfo.systemUptime)
                else {
                    self.invalidate()
                    return
                }
                self.publish()
                try await Task.sleep(for: .seconds(BrowserLinkHoverState.expansionDelay))
                guard !Task.isCancelled, self.state.ticket == ticket else { return }
                let remainsValid = await self.validate(document: document, sequence: sequence, href: href, frame: frame)
                guard !Task.isCancelled, self.state.ticket == ticket else { return }
                guard remainsValid, self.canPresent,
                    self.state.expand(ticket: ticket, at: ProcessInfo.processInfo.systemUptime)
                else {
                    self.invalidate()
                    return
                }
                self.publish()
            } catch {
                // Cancellation retires pending work without publishing text.
            }
        }
    }

    /// The link under the pointer as the engine reports it, or nil when the
    /// pointer left it. The engine's own hit testing is authoritative, so
    /// there is no document to validate against.
    func receiveEngineHover(_ url: URL?) {
        if let host = contentView?.superview { attach(to: host) }
        engineSequence &+= 1
        let sequence = engineSequence
        guard let href = url?.absoluteString else {
            state.leave(document: "engine", sequence: sequence)
            work?.cancel()
            work = nil
            publish()
            return
        }
        guard canPresent, BrowserLinkHoverDestination(resolvedURL: href) != nil else {
            invalidate()
            return
        }
        work?.cancel()
        let ticket = state.receive(
            document: "engine", sequence: sequence, href: href,
            at: ProcessInfo.processInfo.systemUptime
        )
        publish()
        work = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(BrowserLinkHoverState.appearanceDelay))
                guard let self, !Task.isCancelled, self.state.ticket == ticket, self.canPresent,
                    self.state.reveal(ticket: ticket, at: ProcessInfo.processInfo.systemUptime)
                else { return }
                self.publish()
                try await Task.sleep(for: .seconds(BrowserLinkHoverState.expansionDelay))
                guard !Task.isCancelled, self.state.ticket == ticket, self.canPresent,
                    self.state.expand(ticket: ticket, at: ProcessInfo.processInfo.systemUptime)
                else { return }
                self.publish()
            } catch {
                // Cancellation retires pending work without publishing text.
            }
        }
    }

    private func validate(document: String, sequence: Int, href: String, frame: WKFrameInfo) async -> Bool {
        guard let webView else { return false }
        let result = try? await webView.callAsyncJavaScript(
            BrowserLinkHoverContentBridge.validation,
            arguments: ["documentID": document, "sequence": sequence, "href": href],
            in: frame, contentWorld: BrowserLinkHoverContentBridge.world
        )
        return result as? Bool == true
    }

    private var canPresent: Bool {
        guard !isNavigating, let contentView, let presentationHost,
            contentView.superview === presentationHost, !contentView.isHiddenOrHasHiddenAncestor,
            let window = contentView.window, window.isKeyWindow, NSApp.isActive,
            window.attachedSheet == nil, !BrowserMenuTrackingMonitor.shared.isTracking,
            let content = window.contentView
        else { return false }
        let point = content.convert(window.mouseLocationOutsideOfEventStream, from: nil)
        guard let hit = content.hitTest(point) else { return false }
        return hit === contentView || hit.isDescendant(of: contentView)
    }

    private func publish() {
        if destination != state.destination { destination = state.destination }
        if isExpanded != state.isExpanded { isExpanded = state.isExpanded }
    }
}
