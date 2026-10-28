import Foundation

/// A link an engine staged for a new page's first load, which keeps the
/// referrer and initiator it had where it was followed.
struct BrowserEngineNavigation: Equatable, Sendable {
    let implementation: BrowserEngineImplementation
    /// The engine's identity for the link it staged.
    let linkID: UUID
    /// The core's page the link was followed in, for an engine whose staged
    /// links go through the core; nil for one that keeps them itself.
    var sourcePageID: UUID?
}
