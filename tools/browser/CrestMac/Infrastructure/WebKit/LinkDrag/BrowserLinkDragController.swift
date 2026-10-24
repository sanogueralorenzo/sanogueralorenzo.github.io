import AppKit
import Observation
import WebKit

/// Connects an engine's claimed link drag to AppKit pointer and window events.
@MainActor
final class BrowserLinkDragController: BrowserLinkPullReceiver {
    private static let pendingReleaseLifetime: TimeInterval = 0.3
    private static let escapeKeyCode: UInt16 = 53
    private weak var nativeView: NSView?
    private var webView: WKWebView? { nativeView as? WKWebView }
    private let context: () -> BrowserPageNavigationContext?
    /// Whether this device's link preferences drag links into Peek, as the
    /// core last published them.
    private let dragsLinksToPeek: () -> Bool
    private let pullHandler: BrowserLinkPullHandler
    private var frames: [String: WKFrameInfo] = [:]
    private var gesture: Gesture?
    private var eventMonitor: Any?
    private var nativeMouseDownMonitor: Any?
    private var windowObserver: NSObjectProtocol?
    private var mouseDownLocation: CGPoint?
    private var mouseDownAllowsNativeDrag = false
    private var pendingMouseUp: NSEvent?
    private var pendingMouseUpTime: TimeInterval?
    private var isNavigating = false
    private var releaseGeneration = 0

    private struct Gesture {
        let document: String
        let window: NSWindow
    }

    init(
        webView: WKWebView,
        context: @escaping () -> BrowserPageNavigationContext?,
        dragsLinksToPeek: @escaping () -> Bool,
        handle: @escaping (BrowserPeekInteractionEvent) -> Void
    ) {
        self.nativeView = webView
        self.context = context
        self.dragsLinksToPeek = dragsLinksToPeek
        pullHandler = BrowserLinkPullHandler(context: context, handle: handle)
        observePreference()
    }

    init(
        nativeView: NSView, context: @escaping () -> BrowserPageNavigationContext?,
        dragsLinksToPeek: @escaping () -> Bool, handle: @escaping (BrowserPeekInteractionEvent) -> Void
    ) {
        self.nativeView = nativeView
        self.context = context
        self.dragsLinksToPeek = dragsLinksToPeek
        pullHandler = BrowserLinkPullHandler(context: context, handle: handle)
    }

    isolated deinit {
        removeMonitors()
        if let nativeMouseDownMonitor { NSEvent.removeMonitor(nativeMouseDownMonitor) }
    }

    func observeNativeMouseDown() {
        guard nativeMouseDownMonitor == nil else { return }
        nativeMouseDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self, let view = self.nativeView, event.window === view.window,
                    let content = view.window?.contentView
                else { return }
                let point = content.superview?.convert(event.locationInWindow, from: nil) ?? event.locationInWindow
                guard let hit = content.hitTest(point),
                    hit === view || hit.isDescendant(of: view)
                else { return }
                self.mouseDown(event)
                let flags = event.modifierFlags
                self.mouseDownAllowsNativeDrag =
                    !flags.contains(.command) && !flags.contains(.control)
                    && self.dragsLinksToPeek() != flags.contains(.option)
            }
            return event
        }
    }

    /// Called only for a renderer URL drag that passed Chromium's drag policy.
    func beginNativeLink(url: URL, label: String?) -> Bool {
        guard mouseDownAllowsNativeDrag else { return false }
        return begin(url: url, label: label, document: "native", dragOffset: nil)
    }

    func mouseDown(_ event: NSEvent) {
        cancel()
        mouseDownLocation = event.locationInWindow
        pendingMouseUp = nil
        pendingMouseUpTime = nil
        if let window = event.window { installMonitors(window: window) }
    }

    func beginNavigation() {
        isNavigating = true
        cancel()
        for frame in frames.values { configure(frame) }
    }

    func didFinishNavigation() {
        isNavigating = false
        for frame in frames.values { configure(frame) }
    }

    func contextDidChange() {
        if pullHandler.validateSource() { return }
        cancel()
        for frame in frames.values { configure(frame) }
    }

    func detach() {
        cancel()
        if let nativeMouseDownMonitor { NSEvent.removeMonitor(nativeMouseDownMonitor) }
        nativeMouseDownMonitor = nil
        mouseDownLocation = nil
        pendingMouseUp = nil
        pendingMouseUpTime = nil
    }

    func receive(_ message: WKScriptMessage) {
        guard message.webView === webView, message.name == BrowserLinkDragContentBridge.name,
            let body = BrowserLinkPullMessage(message.body, requiresVersion: true)
        else { return }
        body.phase.apply(body, from: message.frameInfo, to: self)
    }

    func ready(_ message: BrowserLinkPullMessage, from frame: WKFrameInfo) {
        frames[message.document] = frame
        configure(frame)
    }

    func retire(_ message: BrowserLinkPullMessage) {
        frames[message.document] = nil
        if gesture?.document == message.document { cancel() }
    }

    func begin(_ message: BrowserLinkPullMessage) {
        guard frames[message.document] != nil, let url = message.url else { return }
        _ = begin(url: url, label: message.label, document: message.document, dragOffset: message.dragOffset)
    }

    private func begin(url: URL, label: String?, document: String, dragOffset: CGPoint?) -> Bool {
        guard gesture == nil, !isNavigating,
            let nativeView, !nativeView.isHiddenOrHasHiddenAncestor,
            let window = nativeView.window, window.isKeyWindow, NSApp.isActive,
            window.attachedSheet == nil,
            mouseDownLocation != nil || NSEvent.pressedMouseButtons & 1 != 0,
            pendingMouseUpTime.map({
                ProcessInfo.processInfo.systemUptime - $0 < Self.pendingReleaseLifetime
            }) ?? true,
            let content = window.contentView,
            content.bounds.width > 0, content.bounds.height > 0
        else { return false }
        let current = normalizedPoint(window.mouseLocationOutsideOfEventStream, in: content)
        let origin: CGPoint
        if let mouseDownLocation {
            origin = normalizedPoint(mouseDownLocation, in: content)
        } else {
            guard let offset = dragOffset, let webView else { return false }
            origin = CGPoint(
                x: current.x - offset.x * webView.pageZoom / content.bounds.width,
                y: current.y - offset.y * webView.pageZoom / content.bounds.height)
        }
        guard
            pullHandler.begin(
                url: url, label: label, origin: origin,
                sample: BrowserLinkPullSample(
                    location: current, size: content.bounds.size,
                    time: ProcessInfo.processInfo.systemUptime))
        else { return false }
        gesture = Gesture(document: document, window: window)
        installMonitors(window: window)
        if let pendingMouseUp { track(pendingMouseUp) }
        return true
    }

    private func installMonitors(window: NSWindow) {
        removeMonitors()
        eventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDragged, .leftMouseUp, .keyDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] event in
            let consumesEvent = MainActor.assumeIsolated {
                guard let self else { return false }
                if event.type == .keyDown && event.keyCode == Self.escapeKeyCode {
                    let hadGesture = self.gesture != nil
                    self.cancel()
                    return hadGesture
                }
                if event.type == .leftMouseDragged || event.type == .leftMouseUp {
                    self.track(event)
                } else if event.type != .keyDown {
                    self.cancel()
                }
                return false
            }
            return consumesEvent ? nil : event
        }
        windowObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: window, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.cancel() }
        }
    }

    private func track(_ event: NSEvent) {
        guard let current = gesture else {
            if event.type == .leftMouseUp {
                pendingMouseUp = event
                pendingMouseUpTime = ProcessInfo.processInfo.systemUptime
                removeMonitors()
            }
            return
        }
        guard let nativeView, nativeView.window === current.window,
            event.window === current.window, let content = current.window.contentView
        else {
            cancel()
            return
        }
        let sample = BrowserLinkPullSample(
            location: normalizedPoint(event.locationInWindow, in: content),
            size: content.bounds.size, time: ProcessInfo.processInfo.systemUptime)
        if event.type == .leftMouseUp {
            let generation = releaseGeneration
            // Let the source engine view receive mouse-up before the committed
            // overlay becomes a hit-test target over that same pointer.
            DispatchQueue.main.async { [weak self] in
                guard let self, self.releaseGeneration == generation else { return }
                self.pullHandler.end(sample)
            }
            gesture = nil
            mouseDownLocation = nil
            pendingMouseUp = nil
            pendingMouseUpTime = nil
            removeMonitors()
        } else {
            pullHandler.move(sample)
            if !pullHandler.isActive { cancel() }
        }
    }

    func cancel() {
        releaseGeneration &+= 1
        gesture = nil
        mouseDownAllowsNativeDrag = false
        mouseDownLocation = nil
        pendingMouseUp = nil
        pendingMouseUpTime = nil
        removeMonitors()
        pullHandler.cancel()
    }

    private func removeMonitors() {
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
        eventMonitor = nil
        if let windowObserver { NotificationCenter.default.removeObserver(windowObserver) }
        windowObserver = nil
    }

    private func normalizedPoint(_ point: CGPoint, in content: NSView) -> CGPoint {
        let local = content.convert(point, from: nil)
        let x = (local.x - content.bounds.minX) / content.bounds.width
        let y = (local.y - content.bounds.minY) / content.bounds.height
        return CGPoint(x: x, y: content.isFlipped ? y : 1 - y)
    }

    private func configure(_ frame: WKFrameInfo) {
        webView?.callAsyncJavaScript(
            "globalThis.__crestLinkDrag?.configure(enabled, available);",
            arguments: [
                "enabled": dragsLinksToPeek(),
                "available": context() != nil && !isNavigating,
            ],
            in: frame, in: BrowserLinkDragContentBridge.world, completionHandler: nil
        )
    }

    private func observePreference() {
        withObservationTracking {
            _ = dragsLinksToPeek()
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                for frame in self.frames.values { self.configure(frame) }
                self.observePreference()
            }
        }
    }
}
