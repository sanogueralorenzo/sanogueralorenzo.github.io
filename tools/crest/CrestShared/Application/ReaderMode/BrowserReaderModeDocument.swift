import Foundation

@MainActor
protocol BrowserReaderModeDocument: AnyObject {
    var url: URL? { get }
    func prepareForReaderMode() async throws
    func readerModeIsAvailable() async throws -> Bool
    func activateReaderMode() async throws
    func deactivateReaderMode() async throws
}
