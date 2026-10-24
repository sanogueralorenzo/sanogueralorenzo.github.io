import Foundation

enum BrowserPlatformDownloadDirectory {
    static func resolve(
        suggestedFilename: String,
        spaceID _: UUID,
        forcesPrompt _: Bool = false,
        fileManager: FileManager = .default
    ) async -> any BrowserPlatformDownloadResolution {
        let directory = URL.documentsDirectory
            .appendingPathComponent("Downloads", isDirectory: true)
        return .destination(
            BrowserDownloadDestination.availableURL(
                suggestedFilename: suggestedFilename,
                directory: directory,
                fileExists: { fileManager.fileExists(atPath: $0.path) }
            ),
            securityScopedURL: nil
        )
    }
}
