import Foundation

extension CrestCore {
    /// Records a finished and an active download for a showcase session.
    func addShowcaseDownloads(profileID: UUID) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Crest Showcase Downloads", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let finishedID = UUID()
        let finishedURL = directory.appendingPathComponent("Crest Verification Notes.txt")
        try? Data("Crest download verification fixture\n".utf8).write(to: finishedURL, options: .atomic)
        let finishedBytes = Int64((try? finishedURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        let activeID = UUID()
        let activeURL = directory.appendingPathComponent("Crest Design Review.pdf")
        let intents: [any Intent] = [
            BeginDownload(
                downloadID: finishedID, profileID: profileID, filename: finishedURL.lastPathComponent,
                createdAt: .now.addingTimeInterval(-90), isAcknowledged: false),
            SetDownloadDestination(
                downloadID: finishedID, destination: finishedURL.absoluteString, filename: finishedURL.lastPathComponent
            ),
            FinishDownload(downloadID: finishedID, finalByteCount: finishedBytes),
            BeginDownload(
                downloadID: activeID, profileID: profileID, filename: activeURL.lastPathComponent, createdAt: .now,
                isAcknowledged: false),
            SetDownloadDestination(
                downloadID: activeID, destination: activeURL.absoluteString, filename: activeURL.lastPathComponent),
            RecordDownloadTransfer(
                downloadID: activeID,
                telemetry: DownloadTelemetry(
                    bytesReceived: 8_388_608, totalBytes: 13_107_200, bytesPerSecond: 1_572_864,
                    estimatedTimeRemaining: 3, isPaused: false),
                progress: 0.64),
        ]
        for intent in intents {
            _ = try? send(intent)
        }
    }
}
