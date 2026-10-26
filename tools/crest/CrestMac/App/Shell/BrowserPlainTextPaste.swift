import AppKit

/// Pasting the clipboard as plain text into whatever has focus.
///
/// AppKit text views answer `pasteAsPlainText:`, WebKit's page view does too,
/// and Chromium's page view answers `pasteAndMatchStyle:` instead. The Edit
/// menu's one item, and the page's context menu, ask the responder which of
/// the two it takes.
@MainActor
struct BrowserPlainTextPaste {
    // MARK: - Static Variables

    /// The selectors a responder takes it by, in the order they are tried.
    private static let selectors = [
        #selector(NSTextView.pasteAsPlainText(_:)), Selector(("pasteAndMatchStyle:")),
    ]

    // MARK: - Variables

    let responder: NSResponder
    let selector: Selector

    // MARK: - Initializers

    /// The paste `responder` takes, or nil when it takes neither selector or
    /// has nowhere to paste now, such as a page with no editable focus.
    /// `item` is the menu item that shows the command: a responder that
    /// validates the same selector checks that item, so WebKit, which answers
    /// later, updates the item people see.
    init?(for responder: NSResponder?, validating item: NSMenuItem? = nil) {
        guard let responder,
            let selector = Self.selectors.first(where: { responder.responds(to: $0) })
        else { return nil }
        if let validating = responder as? NSUserInterfaceValidations {
            let checked =
                item.flatMap { $0.action == selector ? $0 : nil }
                ?? NSMenuItem(title: "", action: selector, keyEquivalent: "")
            guard validating.validateUserInterfaceItem(checked) else { return nil }
        }
        self.responder = responder
        self.selector = selector
    }

    // MARK: - Actions - Running

    /// Pastes the clipboard's text into the responder.
    func perform() {
        _ = responder.perform(selector, with: nil)
    }
}
