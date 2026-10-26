import Foundation

/// A question one of a WebKit binding's pages raised with the core, until the
/// core settles it. Each kind of question answers WebKit its own way.
protocol WebKitPendingPrompt {
    /// The page that asked.
    var pageID: UUID { get }

    /// Answers WebKit as nobody accepting or giving anything.
    @MainActor func decline()

    /// The answer that declines the prompt `promptID` through the core.
    func declining(_ promptID: UUID) -> any PromptIntent
}
