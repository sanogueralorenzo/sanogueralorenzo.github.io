import Foundation

enum BrowserDownloadTransfer {
    static func stagingURL(
        itemID: UUID,
        suggestedFilename: String,
        directory: URL
    ) -> URL {
        let safeFilename = BrowserDownloadDestination.safeFilename(
            from: suggestedFilename
        )
        return directory.appendingPathComponent(
            "\(itemID.uuidString)-\(safeFilename)"
        )
    }

    static func finish(
        from stagingURL: URL,
        to destinationURL: URL,
        quarantine: BrowserDownloadQuarantine? = nil,
        fileManager: FileManager = .default
    ) throws {
        try fileManager.moveItem(at: stagingURL, to: destinationURL)
        guard let quarantine else { return }

        do {
            try BrowserPlatformDownloadQuarantine.apply(
                quarantine,
                to: destinationURL
            )
        } catch {
            try? fileManager.removeItem(at: destinationURL)
            throw error
        }
    }
}
