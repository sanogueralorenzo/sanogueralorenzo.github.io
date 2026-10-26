import Foundation

@MainActor
protocol BrowserFaviconDocument: AnyObject {
    var url: URL? { get }
    func observeIconChanges(_ changed: @escaping @MainActor () -> Void)
    func capture() async -> Data?
    func fallback(for url: URL) async -> Data?
}
