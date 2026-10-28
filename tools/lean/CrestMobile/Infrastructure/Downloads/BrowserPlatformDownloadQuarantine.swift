import Foundation

enum BrowserPlatformDownloadQuarantine {
    static func apply(
        _ quarantine: BrowserDownloadQuarantine,
        to destinationURL: URL
    ) throws {
        // iOS applies its own download provenance. Crest only owns the final move.
    }
}
