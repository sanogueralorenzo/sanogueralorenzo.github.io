import Foundation

enum BrowserUtilityListPreviewFixture {
    static let referenceDate = Date(timeIntervalSinceReferenceDate: 807_969_600)
    static let assignment = BrowserSpaceRuntimeAssignment(
        spaceID: identifier(0x21),
        profileID: identifier(0x11)
    )

    static let historyEntry = HistoryEntryState(
        id: identifier(0x31),
        url: previewURL("history").absoluteString,
        title: "Crest Project Notes",
        firstVisitedAt: referenceDate.addingTimeInterval(-3_600),
        lastVisitedAt: referenceDate,
        visitCount: 3
    )

    private static let archivedPreviewTab = ArchivedTabState.Seed(
        tab: TabState.Seed(
            id: identifier(0x41),
            title: "Architecture Notes",
            url: previewURL("archive"),
            symbol: "doc.text.fill",
            iconMode: .pulled,
            placement: .saved,
            lastActivatedAt: referenceDate.addingTimeInterval(-7_200)
        ),
        archivedAt: referenceDate.addingTimeInterval(-1_800),
        reason: .closed
    )

    static let historySpace = SpaceState.Seed(
        id: assignment.spaceID,
        profileID: assignment.profileID,
        name: "Research",
        symbol: "books.vertical.fill",
        accent: .indigo,
        folders: [],
        tabs: [
            TabState.Seed(
                id: identifier(0x42),
                title: "Current Notes",
                url: previewURL("current"),
                symbol: "doc.text",
                iconMode: .pulled,
                placement: .current,
                lastActivatedAt: referenceDate
            )
        ],
        archivedTabs: [archivedPreviewTab],
        history: [historyEntry]
    )

    /// The history Space as the read model of a preview store holds it.
    @MainActor
    static var historySpaceModel: SpaceModel? {
        BrowserStore(
            seed: SessionState.Seed(spaces: [historySpace]),
            images: Dictionary(
                uniqueKeysWithValues: (historySpace.tabs.map(\.id) + historySpace.archivedTabs.map(\.tab.id)).map {
                    ($0, inlineFaviconData)
                }), showing: historySpace.id
        ).spaceModel(
            historySpace.id)
    }

    static let preparingDownload = download(
        id: identifier(0x51),
        filename: "Crest.dmg",
        phase: .preparing
    )

    static let activeDownload = download(
        id: identifier(0x52),
        filename: "Crest.dmg",
        progress: 0.64,
        phase: .downloading
    )

    static let finishedDownload = download(
        id: identifier(0x53),
        filename: "Crest.dmg",
        progress: 1,
        phase: .finished
    )

    static let failedDownload = download(
        id: identifier(0x54),
        filename: "Crest.dmg",
        phase: .failed,
        message: "The connection was interrupted."
    )

    static var fixedCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        if let timeZone = TimeZone(secondsFromGMT: 0) {
            calendar.timeZone = timeZone
        }
        return calendar
    }

    private static func download(
        id: UUID,
        filename: String,
        progress: Double = 0,
        phase: DownloadPhase,
        message: String? = nil
    ) -> DownloadState {
        DownloadState(
            id: id,
            profileID: assignment.profileID,
            createdAt: referenceDate,
            filename: filename,
            destination: URL(filePath: "/crest-preview/\(filename)").absoluteString,
            progress: progress,
            telemetry: DownloadTelemetry(
                bytesReceived: 0, totalBytes: nil, bytesPerSecond: nil, estimatedTimeRemaining: nil, isPaused: false),
            phase: phase,
            failure: nil,
            message: message,
            risk: nil,
            isAcknowledged: false, canPause: false, canResume: false
        )
    }

    private static func identifier(_ finalByte: UInt8) -> UUID {
        UUID(
            uuid: (
                0, 0, 0, 0, 0, 0, 0x40, 0,
                0x80, 0, 0, 0, 0, 0, 0, finalByte
            )
        )
    }

    private static func previewURL(_ path: String) -> URL {
        guard let url = URL(string: "crest-preview://utility/\(path)") else {
            preconditionFailure("Browser Utility preview URL is invalid")
        }
        return url
    }

    private static let inlineFaviconData = Data([
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
        0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
        0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
        0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
        0x89, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x44, 0x41,
        0x54, 0x08, 0xD7, 0x63, 0x60, 0x68, 0xF8, 0xCF,
        0xF0, 0x1F, 0x00, 0x05, 0x00, 0x01, 0xFF, 0x89,
        0x99, 0x3D, 0x1D, 0x00, 0x00, 0x00, 0x00, 0x49,
        0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
    ])
}
