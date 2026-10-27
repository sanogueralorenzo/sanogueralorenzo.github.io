import Foundation

// MARK: - Types

struct BrowserIntegrationResponse: Sendable {
    let url: URL
    let status: Int
    let data: Data
}

enum BrowserIntegrationSessionFailure: Error, Equatable {
    case invalidRequest
    case invalidResponse
    case sessionChanged
}

/// An engine-owned, origin-bound HTTP session. Implementations keep credentials
/// in memory, validate ownership before requests and publication, and never follow a
/// redirect with credentials. Consumers receive only bounded response bodies.
@MainActor
protocol BrowserIntegrationSession: AnyObject {
    var revision: Int { get }
    func get(_ url: URL, accept: String) async throws -> BrowserIntegrationResponse
    func validate() async throws
    func invalidate()
}
