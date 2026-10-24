import AppKit
import os

struct BrowserWebFocusRestorationGate: Equatable {
    let browserChromeOwnsFocus: Bool
    let pageChromeOwnsFocus: Bool

    static let suppressed = BrowserWebFocusRestorationGate(
        browserChromeOwnsFocus: true,
        pageChromeOwnsFocus: false
    )

    var allowsWebPageFocus: Bool {
        !browserChromeOwnsFocus && !pageChromeOwnsFocus
    }

    /// Whether a remembered responder may take focus back through this gate,
    /// with everything else that could own focus at that moment.
    func allowsRestoration(
        hasPendingCandidate: Bool,
        candidateBelongsToWebView: Bool,
        windowIsKey: Bool,
        applicationIsActive: Bool,
        windowHasAttachedSheet: Bool,
        menuIsTracking: Bool,
        accessibilityOwnsFocus: Bool,
        currentOwner: BrowserWebFocusRestorationCurrentOwner
    ) -> Bool {
        hasPendingCandidate
            && candidateBelongsToWebView
            && allowsWebPageFocus
            && windowIsKey
            && applicationIsActive
            && !windowHasAttachedSheet
            && !menuIsTracking
            && !accessibilityOwnsFocus
            && currentOwner != .other
    }
}

enum BrowserWebFocusRestorationCurrentOwner: Equatable {
    case neutral
    case webContent
    case departingWebContent
    case other
}

@MainActor
final class BrowserMenuTrackingMonitor {
    static let shared = BrowserMenuTrackingMonitor()

    private var observationTokens: [NSObjectProtocol] = []
    private var trackingDepth = 0

    var isTracking: Bool { trackingDepth > 0 }

    init(notificationCenter: NotificationCenter = .default) {
        observationTokens = [
            notificationCenter.addObserver(
                forName: NSMenu.didBeginTrackingNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.trackingDepth += 1
                }
            },
            notificationCenter.addObserver(
                forName: NSMenu.didEndTrackingNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.trackingDepth = max(0, self.trackingDepth - 1)
                }
            },
        ]
    }
}

/// Remembers the engine's public AppKit responder, never a DOM node.
///
/// An engine keeps the focused element, caret, and selection in a resident view
/// while Crest moves that view between SwiftUI hosts. Restoring the same native
/// responder lets it resume its own editing session without scripting the
/// page or bypassing its security-sensitive focus rules.
@MainActor
final class BrowserWebFocusRestorationController {
    private weak var webView: NSView?
    private weak var candidate: NSView?
    private weak var permittedOutgoingWebView: NSView?
    private(set) var hasPendingRestoration = false
    private var presentationFocusProtectionGeneration = 0
    private(set) var allowsNativeFocusAcquisition = true

    init(webView: NSView) {
        self.webView = webView
    }

    func remember(_ responder: NSView) {
        guard let webView,
            Self.isView(responder, containedIn: webView)
        else { return }
        candidate = responder
    }

    func captureBeforeDeparture() {
        guard let webView, let window = webView.window else {
            invalidate()
            return
        }
        guard let responder = window.firstResponder as? NSView,
            Self.isView(responder, containedIn: webView)
        else {
            if window.firstResponder == nil || window.firstResponder === window,
                validCandidate() != nil
            {
                return
            }
            invalidate()
            return
        }

        remember(responder)
        hasPendingRestoration = false
    }

    /// Takes the responder already inside the web view as the page's own,
    /// when focus reached the page ahead of the selection that makes it the
    /// focused one, as a click in an unfocused split card does. Nothing is
    /// left to restore, so an older candidate cannot take focus from it.
    func adoptCurrentFocus() -> Bool {
        guard let webView, let responder = webView.window?.firstResponder as? NSView,
            Self.isView(responder, containedIn: webView)
        else { return false }
        candidate = responder
        permittedOutgoingWebView = nil
        hasPendingRestoration = false
        return true
    }

    /// Asks for the page itself to take focus once its chrome lets go, as
    /// closing find does: the responder it last held, or its own view when it
    /// never held one, since an engine that keeps no record of its responder,
    /// as Chromium does not, focuses its page from there. A page that already
    /// holds focus keeps the responder it has. Focus may be taken from
    /// `outgoingWebView`, a page giving way to this one, as a closing Peek is.
    func requestPageFocus(displacing outgoingWebView: NSView? = nil) {
        guard let webView, !adoptCurrentFocus() else { return }
        if validCandidate() == nil { candidate = webView }
        permittedOutgoingWebView = outgoingWebView
        hasPendingRestoration = true
    }

    func requestRestoration(displacing outgoingWebView: NSView? = nil) {
        guard validCandidate() != nil else {
            hasPendingRestoration = false
            permittedOutgoingWebView = nil
            return
        }
        permittedOutgoingWebView = outgoingWebView
        hasPendingRestoration = true
    }

    func invalidate() {
        candidate = nil
        permittedOutgoingWebView = nil
        hasPendingRestoration = false
    }

    func beginPresentationFocusProtection() -> Int {
        // SwiftUI can replay an NSViewRepresentable's prior focus during the
        // layout that mounts an active tab. Suppress only that presentation
        // turn when chrome already owns focus; the next user event is free to
        // focus the page normally.
        presentationFocusProtectionGeneration &+= 1
        allowsNativeFocusAcquisition = false
        return presentationFocusProtectionGeneration
    }

    func endPresentationFocusProtection(generation: Int) {
        guard generation == presentationFocusProtectionGeneration else { return }
        allowsNativeFocusAcquisition = true
    }

    @discardableResult
    func restoreIfNeeded(
        in host: NSView,
        gate: BrowserWebFocusRestorationGate,
        applicationIsActive: Bool = NSApp.isActive,
        accessibilityOwnsFocus: Bool =
            NSWorkspace.shared.isVoiceOverEnabled
            || NSApp.isFullKeyboardAccessEnabled,
        menuIsTracking: Bool = BrowserMenuTrackingMonitor.shared.isTracking,
        windowIsKey: Bool? = nil
    ) -> Bool {
        guard hasPendingRestoration, webView != nil else { return false }
        guard let window = host.window else { return false }
        guard let candidate = validCandidate() else {
            invalidate()
            return false
        }
        guard let candidateWindow = candidate.window else {
            // The same live engine view may not have completed its new host
            // attachment yet. `viewDidMoveToWindow` supplies the next chance.
            return false
        }
        guard candidateWindow === window else {
            invalidate()
            return false
        }

        let currentOwner = currentOwner(
            window.firstResponder,
            candidate: candidate,
            host: host
        )
        let allowsRestoration =
            gate.allowsRestoration(
                hasPendingCandidate: true,
                candidateBelongsToWebView: true,
                windowIsKey: windowIsKey ?? window.isKeyWindow,
                applicationIsActive: applicationIsActive,
                windowHasAttachedSheet: window.attachedSheet != nil,
                menuIsTracking: menuIsTracking,
                accessibilityOwnsFocus: accessibilityOwnsFocus,
                currentOwner: currentOwner
            )

        guard allowsRestoration else {
            // Every condition here represents an authoritative focus owner,
            // an inactive presentation, or a stale candidate. Do not turn it
            // into a delayed focus steal.
            invalidate()
            return false
        }

        hasPendingRestoration = false
        permittedOutgoingWebView = nil
        guard window.makeFirstResponder(candidate) else {
            invalidate()
            return false
        }
        return true
    }

    private func validCandidate() -> NSView? {
        guard let webView, let candidate,
            Self.isView(candidate, containedIn: webView)
        else { return nil }
        return candidate
    }

    private func currentOwner(
        _ responder: NSResponder?,
        candidate: NSView?,
        host: NSView
    ) -> BrowserWebFocusRestorationCurrentOwner {
        if responder == nil || responder === host.window || responder === host {
            return .neutral
        }
        if let candidate, responder === candidate {
            return .webContent
        }
        if let webView, let view = responder as? NSView,
            Self.isView(view, containedIn: webView)
        {
            return .webContent
        }
        if let permittedOutgoingWebView, let view = responder as? NSView,
            Self.isView(view, containedIn: permittedOutgoingWebView)
        {
            return .departingWebContent
        }
        return .other
    }

    private static func isView(_ view: NSView, containedIn ancestor: NSView) -> Bool {
        view === ancestor || view.isDescendant(of: ancestor)
    }
}

/// How a window shows the page in one of its hosts.
enum BrowserPagePresentation {
    /// Off screen, in a Space the window does not show. The Space keeps its
    /// page's view in its host so the page keeps its place, but the page's
    /// engine treats it as hidden, as it does a tab the person switched away
    /// from.
    case hidden
    /// On screen in a Space the person swipes to or from, which draws the
    /// page as it moves. The engine keeps rendering the page, which takes no
    /// input or focus until its Space settles.
    case preview
    /// The page the window presents to the person.
    case presented
}

/// Optional engine hooks. The host owns AppKit attachment and focus; an
/// adapter owns engine-specific observers such as WebKit's link-hover overlay.
@MainActor
protocol BrowserNativePageSurfaceLifecycle: AnyObject {
    func didAttach(to host: BrowserWebHostView)
    func willDetach(from host: BrowserWebHostView)
    /// The host showing this view changed how it shows its page, as its
    /// Space did, while the view stayed in it; see
    /// `BrowserWebHostView.presentation`.
    func presentationDidChange(in host: BrowserWebHostView)
    func presentationGeometryDidChange()
    /// Whether a page this view gives way to should stay on screen above the
    /// view that replaces it until that one has drawn. An engine whose page
    /// draws nothing for a few frames after it is shown again sets it, so a
    /// tab switch never shows the page's bare background in between.
    var holdsReplacedPageUntilDrawn: Bool { get }
}

extension BrowserNativePageSurfaceLifecycle {
    func presentationDidChange(in host: BrowserWebHostView) {}
    func presentationGeometryDidChange() {}
    var holdsReplacedPageUntilDrawn: Bool { false }
}

/// Shows a page's engine-owned view where SwiftUI placed this host.
///
/// SwiftUI can hold two hosts for one page at once, and either can be the one
/// it dismantles first. It keeps updating an outgoing host after the incoming
/// one claimed the view, and an outgoing subtree that still renders during its
/// removal, such as the window's chrome giving way to a page shown fullscreen,
/// can build a host for the page after the incoming one did. The newest claim
/// shows the view, a stale update never takes it back, and when the host
/// showing it lets go, the view returns to the newest host still claiming it
/// in the same window, so it always ends up in whichever host survives. A
/// host in another window keeps waiting for its own window to present the
/// page again.
@MainActor
final class BrowserWebHostView: NSView {
    // MARK: - Static Variables

    private static let lifecycleSignposter = OSSignposter(
        subsystem: "com.pauldavis.crest",
        category: "BrowserSurfaceLifecycle"
    )
    /// Every host that claimed a page view and has not let it go.
    private static let claimants = NSHashTable<BrowserWebHostView>.weakObjects()
    /// The number of claims made so far, which orders them.
    private static var claimCount = 0
    /// How many display frames a replaced page stays above the page that
    /// replaced it: about 42 ms at 120 Hz, longer than the frames a page
    /// shown again takes to draw.
    private static let replacementHoldFrames = 5

    // MARK: - Variables

    private weak var hostedWebView: NSView?
    private(set) weak var focusRestoration: BrowserWebFocusRestorationController?
    /// The window this host was last in, which it keeps while SwiftUI takes it
    /// out of the window on its way to being dismantled.
    private weak var lastWindow: NSWindow?
    /// Keeps the window server from dragging the window by this page's top.
    private lazy var titleBarTracker = BrowserPageTitleBarTracker(page: self)
    private var titleBarTrackingArea: NSTrackingArea?
    private var focusRestorationGate = BrowserWebFocusRestorationGate.suppressed
    private var isPageActive = false
    /// How the window shows this host's page. A Space keeps its page's view
    /// in its host whether the window shows the Space or not, so the page
    /// keeps its place and its Space's preview draws it as the person swipes.
    private(set) var presentation = BrowserPagePresentation.presented
    private var focusRestorationAttemptGeneration = 0
    /// When this host claimed `hostedWebView`: the newest claim is the largest.
    private var claim = 0
    /// The page view this host showed before `hostedWebView`, still shown
    /// above it while the new one draws its first frames; see
    /// `holdsReplacedPageUntilDrawn`.
    private var replacedWebView: NSView?
    private var replacedFramesLeft = 0
    private var replacedDisplayLink: CADisplayLink?

    // MARK: - Actions - Hosting

    /// Claims `webView` and shows it here, unless `allowsAttachment` says this
    /// host's window no longer presents the page, which lets it go. Asking
    /// again for the view this host already claimed changes nothing, even when
    /// a newer host took it meanwhile: that host shows it until it lets go.
    func attach(
        _ webView: NSView,
        focusRestoration: BrowserWebFocusRestorationController? = nil,
        allowsAttachment: Bool = true
    ) {
        guard allowsAttachment else {
            detach()
            return
        }
        if hostedWebView === webView {
            if webView.superview === self {
                self.focusRestoration = focusRestoration
                return
            }
            if webView.superview != nil {
                // A newer SwiftUI host has already taken ownership. A stale
                // update from a disappearing Peek must not steal it back.
                // Keep the claim so repeated updates remain stale; an
                // unattached view can still return through the path below.
                self.focusRestoration = nil
                isPageActive = false
                return
            }
        }

        let attachInterval = Self.lifecycleSignposter.beginInterval(
            "Attach Page View"
        )
        defer {
            Self.lifecycleSignposter.endInterval(
                "Attach Page View",
                attachInterval
            )
        }

        let detachInterval = Self.lifecycleSignposter.beginInterval(
            "Detach Previous Page View"
        )
        let replaced = replaceableWebView()
        if let replaced {
            letGo(keepingOnScreen: replaced)
        } else {
            detach()
        }
        Self.lifecycleSignposter.endInterval(
            "Detach Previous Page View",
            detachInterval
        )
        Self.claimCount &+= 1
        claim = Self.claimCount
        hostedWebView = webView
        Self.claimants.add(self)
        show(webView, focusRestoration: focusRestoration, below: replaced)
        if let replaced { holdUntilReplacementDraws(replaced) }
    }

    /// Lets go of the view this host claimed. When it was showing it, the view
    /// leaves and moves to the newest other host in its window that still
    /// claims it.
    func detach() {
        releaseReplacedWebView()
        guard let hostedWebView else { return }
        Self.claimants.remove(self)
        let showsHostedWebView = hostedWebView.superview === self
        if showsHostedWebView {
            (hostedWebView as? any BrowserNativePageSurfaceLifecycle)?.willDetach(from: self)
            hostedWebView.removeFromSuperview()
        }
        let focusRestoration = focusRestoration
        let placement = window ?? lastWindow
        self.hostedWebView = nil
        self.focusRestoration = nil
        isPageActive = false
        focusRestorationAttemptGeneration &+= 1
        guard showsHostedWebView else { return }
        Self.claimants.allObjects
            .filter { $0.hostedWebView === hostedWebView && $0.isPlaced(with: placement) }
            .max { $0.claim < $1.claim }?
            .show(hostedWebView, focusRestoration: focusRestoration)
    }

    /// Whether this host is in `window`, or either has yet to join one.
    private func isPlaced(with window: NSWindow?) -> Bool {
        guard let window, let placement = self.window ?? lastWindow else { return true }
        return placement === window
    }

    // MARK: - Actions - Replacement

    /// The view this host shows now, when the view replacing it should wait
    /// beneath it until it draws: it is on screen here, asks for that, and
    /// no other host claims it, which would take it once this host lets go.
    /// A replacement still in progress ends first.
    private func replaceableWebView() -> NSView? {
        releaseReplacedWebView()
        guard let hostedWebView, hostedWebView.superview === self, window != nil,
            (hostedWebView as? any BrowserNativePageSurfaceLifecycle)?.holdsReplacedPageUntilDrawn == true,
            !Self.claimants.allObjects.contains(where: { $0 !== self && $0.hostedWebView === hostedWebView })
        else { return nil }
        return hostedWebView
    }

    /// Lets go of `webView` as `detach` does, but leaves it on screen.
    private func letGo(keepingOnScreen webView: NSView) {
        Self.claimants.remove(self)
        hostedWebView = nil
        focusRestoration = nil
        isPageActive = false
        focusRestorationAttemptGeneration &+= 1
    }

    /// Keeps `webView` above its replacement for a few display frames: a
    /// page shown again draws nothing until its engine composes a frame for
    /// it, about two to four frames, and the one it replaces covers that
    /// instead of the page's bare background.
    private func holdUntilReplacementDraws(_ webView: NSView) {
        replacedWebView = webView
        replacedFramesLeft = Self.replacementHoldFrames
        let link = displayLink(target: self, selector: #selector(replacementFrameElapsed(_:)))
        link.add(to: .main, forMode: .common)
        replacedDisplayLink = link
    }

    @objc private func replacementFrameElapsed(_ link: CADisplayLink) {
        replacedFramesLeft -= 1
        if replacedFramesLeft <= 0 { releaseReplacedWebView() }
    }

    /// Takes the replaced view off screen, which hides its page.
    private func releaseReplacedWebView() {
        replacedDisplayLink?.invalidate()
        replacedDisplayLink = nil
        guard let replaced = replacedWebView else { return }
        replacedWebView = nil
        guard replaced.superview === self else { return }
        (replaced as? any BrowserNativePageSurfaceLifecycle)?.willDetach(from: self)
        replaced.removeFromSuperview()
    }

    // MARK: - Actions - Showing

    /// Puts `webView`, which this host claimed, on screen here, beneath
    /// `replaced` while that one is held there.
    private func show(
        _ webView: NSView, focusRestoration: BrowserWebFocusRestorationController?, below replaced: NSView? = nil
    ) {
        self.focusRestoration = focusRestoration ?? self.focusRestoration

        let removeInterval = Self.lifecycleSignposter.beginInterval(
            "Remove Page View From Parent"
        )
        webView.removeFromSuperview()
        Self.lifecycleSignposter.endInterval(
            "Remove Page View From Parent",
            removeInterval
        )

        // WebKit temporarily reparents rendering surfaces for features such as
        // the docked Web Inspector. Frame-based layout lets those surfaces keep
        // their geometry instead of inheriting constraints from the SwiftUI
        // host and ending up mounted but visually blank.
        webView.translatesAutoresizingMaskIntoConstraints = true
        webView.autoresizingMask = [.width, .height]
        if !bounds.isEmpty {
            webView.frame = bounds
        }

        let addInterval = Self.lifecycleSignposter.beginInterval(
            "Add Page View Subview"
        )
        if let replaced, replaced.superview === self {
            addSubview(webView, positioned: .below, relativeTo: replaced)
        } else {
            addSubview(webView)
        }
        Self.lifecycleSignposter.endInterval(
            "Add Page View Subview",
            addInterval
        )
        (webView as? any BrowserNativePageSurfaceLifecycle)?.didAttach(to: self)
    }

    /// Whether the page may take focus as it comes back on screen: it is its
    /// window's focused page and nothing of Crest's, such as the address
    /// field or the command palette, owns focus.
    var allowsPageFocus: Bool { isPageActive && focusRestorationGate.allowsWebPageFocus }

    // MARK: - Actions - Presentation

    /// Tells the page's engine the window changed how it shows the page: the
    /// page left the screen or came back, as a tab switch does by moving the
    /// page's view out of and into a host, or its Space's preview settled.
    /// The view stays here all along.
    func updatePresentation(_ presentation: BrowserPagePresentation) {
        guard presentation != self.presentation else { return }
        self.presentation = presentation
        guard let hostedWebView, hostedWebView.superview === self else { return }
        (hostedWebView as? any BrowserNativePageSurfaceLifecycle)?.presentationDidChange(in: self)
    }

    // MARK: - Actions - Focus

    func updateFocusPresentation(
        isPageActive: Bool,
        gate: BrowserWebFocusRestorationGate
    ) {
        self.isPageActive = isPageActive
        focusRestorationGate = gate
        focusRestorationAttemptGeneration &+= 1

        if isPageActive {
            scheduleFocusRestoration()
        }
        if !isPageActive || !gate.allowsWebPageFocus,
            let focusRestoration
        {
            let protectionGeneration =
                focusRestoration.beginPresentationFocusProtection()
            DispatchQueue.main.async { [weak focusRestoration] in
                focusRestoration?.endPresentationFocusProtection(
                    generation: protectionGeneration
                )
            }
        }
    }

    private func scheduleFocusRestoration() {
        focusRestorationAttemptGeneration &+= 1
        let generation = focusRestorationAttemptGeneration
        DispatchQueue.main.async { [weak self] in
            guard let self,
                self.focusRestorationAttemptGeneration == generation,
                self.isPageActive,
                self.hostedWebView?.superview === self
            else { return }
            self.focusRestoration?.restoreIfNeeded(
                in: self,
                gate: self.focusRestorationGate
            )
        }
    }

    // MARK: - Actions - Keyboard

    /// Whether `responder` is a page's own view shown in a host, or a view
    /// inside it, such as the engine's content view or an inspector docked
    /// beside the page, rather than one of Crest's.
    static func isPageContent(_ responder: NSResponder?) -> Bool {
        var view = responder as? NSView
        while let current = view, let superview = current.superview {
            if let host = superview as? BrowserWebHostView { return host.hostedWebView === current }
            view = superview
        }
        return false
    }

    override func keyDown(with event: NSEvent) {
        guard let hostedWebView,
            let responder = window?.firstResponder as? NSView,
            responder === hostedWebView || responder.isDescendant(of: hostedWebView)
        else {
            super.keyDown(with: event)
            return
        }

        // The engine has already offered this key to the page and its input
        // context. Preserve native fallback handlers without interpreting or
        // dispatching the key to the engine again. Only the terminal, unhandled
        // key-down feedback is unnecessary in a browsing view.
        let fallback = BrowserWebKeyboardFallback()
        var tail: NSResponder = self
        while let next = tail.nextResponder {
            tail = next
        }
        tail.nextResponder = fallback
        defer {
            if tail.nextResponder === fallback {
                tail.nextResponder = fallback.nextResponder
            }
        }
        super.keyDown(with: event)
    }

    // MARK: - Actions - Layout

    override func layout() {
        super.layout()
        layoutHostedWebView()
        titleBarTracker.checkPointerSoon()
    }

    override func resizeSubviews(withOldSize oldSize: NSSize) {
        // SwiftUI can give an entering or departing host an empty frame. Do
        // not send that transient viewport to the engine's rendering process.
        layoutHostedWebView()
    }

    private func layoutHostedWebView() {
        guard !bounds.isEmpty,
            let hostedWebView,
            hostedWebView.superview === self,
            hostedWebView.frame != bounds
        else { return }
        hostedWebView.frame = bounds
    }

    // MARK: - Actions - Window

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow !== window {
            titleBarTracker.release()
            releaseReplacedWebView()
        }
        super.viewWillMove(toWindow: newWindow)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window { lastWindow = window }
        trackTitleBarPointer()
        guard isPageActive else { return }
        scheduleFocusRestoration()
    }

    override func viewDidHide() {
        super.viewDidHide()
        titleBarTracker.release()
    }

    override func viewDidUnhide() {
        super.viewDidUnhide()
        titleBarTracker.checkPointerSoon()
    }

    private func trackTitleBarPointer() {
        guard window != nil else { return }
        if titleBarTrackingArea == nil {
            let area = titleBarTracker.makeTrackingArea()
            addTrackingArea(area)
            titleBarTrackingArea = area
        }
        titleBarTracker.checkPointerSoon()
    }
}

@MainActor
private final class BrowserWebKeyboardFallback: NSResponder {
    override func noResponder(for eventSelector: Selector) {
        guard eventSelector != #selector(NSResponder.keyDown(with:)) else { return }
        super.noResponder(for: eventSelector)
    }
}
