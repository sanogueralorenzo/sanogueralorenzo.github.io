import AppKit

/// A mouse's Back and Forward buttons, raw buttons 4 and 5, in every window
/// the shell opens: one monitor for the application, ahead of every view.
///
/// The window's content decides what a press does and acts on it at once. A
/// press it took is taken whole: its drags and its release never reach the
/// view under the pointer either, whatever became of the window's content in
/// between. Chromium goes back or forward itself on a Back or Forward release
/// a page leaves alone, so a release let through would move the page a
/// second time. A press the content lets go leaves its drags and release to
/// the view under the pointer.
@MainActor
final class BrowserMacMouseButtons {
    // MARK: - Variables

    /// What a press in an event's window does: the window's content.
    private let navigation: @MainActor (NSEvent) -> (any BrowserMacWindowPointerNavigation)?
    /// The buttons whose press Crest took, until their release.
    private var takenButtons: Set<Int> = []
    private var monitor: Any?

    // MARK: - Initializers

    init(
        navigation: @escaping @MainActor (NSEvent) -> (any BrowserMacWindowPointerNavigation)? = {
            ($0.window as? BrowserMacWindow)?.pointerNavigation
        }
    ) {
        self.navigation = navigation
    }

    // MARK: - Actions - Monitoring

    /// Offers every press, drag and release of the mouse's other buttons to
    /// `take` before any view sees it.
    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(
            matching: [.otherMouseDown, .otherMouseDragged, .otherMouseUp]
        ) { [weak self] event in
            // Only answering nil keeps an event from the view under the pointer.
            self?.take(event) == true ? nil : event
        }
    }

    // MARK: - Actions - Events

    /// Whether Crest takes `event`, a press, drag or release of one of the
    /// mouse's other buttons, from the view under the pointer.
    func take(_ event: NSEvent) -> Bool {
        switch event.type {
        case .otherMouseDown:
            takePress(event)
        case .otherMouseDragged:
            takenButtons.contains(event.buttonNumber)
        case .otherMouseUp:
            takenButtons.remove(event.buttonNumber) != nil
        default:
            false
        }
    }

    private func takePress(_ event: NSEvent) -> Bool {
        // A release the application never saw leaves no claim on the next press.
        takenButtons.remove(event.buttonNumber)
        guard let action = BrowserSidebarMouseButtonAction(buttonNumber: event.buttonNumber),
            navigation(event)?.takePress(action, at: event) == true
        else { return false }
        takenButtons.insert(event.buttonNumber)
        return true
    }
}
