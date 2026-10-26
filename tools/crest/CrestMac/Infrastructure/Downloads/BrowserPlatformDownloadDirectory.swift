import AppKit
import Foundation

@MainActor
enum BrowserPlatformDownloadDirectory {
    static func resolve(
        suggestedFilename: String,
        forcesPrompt: Bool = false,
        fileManager: FileManager = .default
    ) async -> any BrowserPlatformDownloadResolution {
        let safeFilename = BrowserDownloadDestination.safeFilename(
            from: suggestedFilename
        )
        if forcesPrompt {
            let panel = NSSavePanel()
            panel.canCreateDirectories = true
            panel.nameFieldStringValue = safeFilename
            panel.title = "Save Download"
            panel.prompt = "Save"
            let response = await withCheckedContinuation { continuation in
                panel.begin { continuation.resume(returning: $0) }
            }
            guard response == .OK, let destination = panel.url else {
                return .cancelled
            }
            return .destination(
                destination,
                securityScopedURL: destination
            )
        }

        guard
            let downloadsDirectory = fileManager.urls(
                for: .downloadsDirectory,
                in: .userDomainMask
            ).first
        else { return .unavailable }
        return .destination(
            BrowserDownloadDestination.availableURL(
                suggestedFilename: safeFilename,
                directory: downloadsDirectory,
                fileExists: { fileManager.fileExists(atPath: $0.path) }
            ),
            securityScopedURL: nil
        )
    }
}
