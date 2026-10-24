import Foundation

enum BrowserStrongPasswordGenerationError: Error, Equatable, Sendable {
    /// The core rejected the requested length or could not supply a recipe.
    case unavailable
}
