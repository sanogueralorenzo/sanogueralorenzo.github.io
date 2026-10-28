import Foundation

extension UUID {
    /// The lowercase spelling the core stores for identities, such as a custom
    /// search engine's `custom:<uuid>` choice.
    var coreIdentifier: String { uuidString.lowercased() }
}
