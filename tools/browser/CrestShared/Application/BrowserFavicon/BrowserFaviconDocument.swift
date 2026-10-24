import Foundation

@MainActor
protocol BrowserFaviconDocument: AnyObject {
    var url: URL? { get }
    func capture() async -> Data?
    func fallback(for url: URL) async -> Data?
}
