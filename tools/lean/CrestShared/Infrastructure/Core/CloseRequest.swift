import Foundation

/// A request to prepare closing pages, windows or the app, which the core
/// answers with a `CloseReady` naming `requestID`.
protocol CloseRequest: CloseIntent {
    var requestID: UUID { get }
    /// Whether the request prepares to quit the app.
    var quits: Bool { get }
}

extension PrepareToClosePages: CloseRequest {
    var quits: Bool { false }
}

extension PrepareToCloseWindows: CloseRequest {
    var quits: Bool { false }
}

extension PrepareToQuit: CloseRequest {
    var quits: Bool { true }
}
