import Foundation

/// A bar the engine raised for the page — "Stop sharing" while a tab is
/// shared, an extension debugging the browser. It asks for a decision, so
/// Crest shows it in the page until the person answers or the engine
/// withdraws it.
struct BrowserEngineInfoBar: Identifiable, Equatable {
    // MARK: - Types

    enum Response: String {
        case accept, cancel, dismiss
    }

    // MARK: - Variables

    let id: Int
    let message: String
    let acceptTitle: String
    let cancelTitle: String
    let isCloseable: Bool
    /// The bar reports something that lasts, such as a tab being shared, so
    /// the person may hide it until they come back to the page.
    let isMinimizable: Bool

    // MARK: - Initializers

    /// A bar with no message asks nothing, so there is none to show.
    init?(
        id: Int, message: String, acceptTitle: String, cancelTitle: String, isCloseable: Bool,
        isMinimizable: Bool = false
    ) {
        guard !message.isEmpty else { return nil }
        self.id = id
        self.message = message
        self.acceptTitle = acceptTitle
        self.cancelTitle = cancelTitle
        self.isCloseable = isCloseable
        self.isMinimizable = isMinimizable
    }
}

extension InfoBarAnswer {
    /// The engine's answer for the person's response to its bar.
    init(_ response: BrowserEngineInfoBar.Response) {
        switch response {
        case .accept: self = .accept
        case .cancel: self = .cancel
        case .dismiss: self = .dismiss
        }
    }
}
