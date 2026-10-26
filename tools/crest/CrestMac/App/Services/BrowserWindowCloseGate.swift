import AppKit

/// Decides whether a window the person asked to close may close, for either
/// engine's windows. The core asks each page the window's closing would
/// discard whether it may go, which can wait on a question the page puts to
/// the person; the window stays open and usable meanwhile, and closes once
/// every page agreed, without asking again. Asking again while the core asks
/// starts no second preparation, a page that asks to stay keeps the window
/// open, and while the app prepares to quit, or quits, no window closes on
/// request: the quit decides.
@MainActor
final class BrowserWindowCloseGate {
    // MARK: - Variables

    private weak var core: CrestCore?
    /// What closing the window asks the core, or nil when it discards no page
    /// and closes at once.
    private let closing: @MainActor () -> (any CloseRequest)?
    /// The core is asking the window's pages.
    private var isAsking = false
    /// The request is being handed to the core, which answers one with
    /// nothing to wait for, or one it refuses, before taking it returns.
    private var isRequesting = false
    /// The answer the core gave while the request was being handed to it.
    private var answeredAtOnce: Bool?
    /// Every page agreed, so the window's next request closes it unasked.
    private var isApproved = false

    // MARK: - Initializers

    init(core: CrestCore, asking closing: @escaping @MainActor () -> (any CloseRequest)?) {
        self.core = core
        self.closing = closing
    }

    // MARK: - Actions - Closing

    /// Whether the window may close now. When the core has to wait for a
    /// page, answers false and calls `close` once every page agreed; `close`
    /// closes the window without asking this gate again.
    func mayClose(then close: @escaping @MainActor () -> Void) -> Bool {
        if isApproved {
            isApproved = false
            return true
        }
        guard let core else { return true }
        guard !isAsking, !core.isQuitting else { return false }
        guard let request = closing() else { return true }
        isAsking = true
        isRequesting = true
        core.prepareToClose(request) { [weak self] allowed in
            guard let self else { return }
            isAsking = false
            guard !isRequesting else {
                answeredAtOnce = allowed
                return
            }
            guard allowed, self.core?.isQuitting != true else { return }
            isApproved = true
            close()
        }
        isRequesting = false
        defer { answeredAtOnce = nil }
        return answeredAtOnce ?? false
    }
}
