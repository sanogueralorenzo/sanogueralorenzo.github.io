import Foundation

/// What a person asked of one download row. Each action carries the step it
/// takes, so the shell that performs it only says how each step is done, as a
/// `BrowserDownloadActionPerformer`.
struct BrowserUtilityDownloadAction: Sendable {
    // MARK: - Variables

    /// The download the action is for.
    let itemID: UUID

    private let step:
        @MainActor @Sendable (
            any BrowserDownloadActionPerformer, DownloadState, BrowserSpaceRuntimeAssignment
        ) -> Void

    // MARK: - Initializers

    private init(
        itemID: UUID,
        step:
            @escaping @MainActor @Sendable (
                any BrowserDownloadActionPerformer, DownloadState, BrowserSpaceRuntimeAssignment
            ) -> Void
    ) {
        self.itemID = itemID
        self.step = step
    }

    /// Hands the finished file to `destination`.
    static func open(_ itemID: UUID, _ destination: BrowserUtilityDownloadDestination) -> Self {
        Self(itemID: itemID) { performer, item, _ in performer.openDownload(item, in: destination) }
    }

    /// Lets a download the site's choice held back go on.
    static func retry(_ itemID: UUID) -> Self {
        Self(itemID: itemID) { performer, item, assignment in performer.retryDownload(item, matching: assignment) }
    }

    static func pause(_ itemID: UUID) -> Self {
        Self(itemID: itemID) { performer, item, _ in performer.pauseDownload(item) }
    }

    static func resume(_ itemID: UUID) -> Self {
        Self(itemID: itemID) { performer, item, _ in performer.resumeDownload(item) }
    }

    static func cancel(_ itemID: UUID) -> Self {
        Self(itemID: itemID) { performer, item, _ in performer.cancelDownload(item) }
    }

    /// Drops the download from the list.
    static func clear(_ itemID: UUID) -> Self {
        Self(itemID: itemID) { performer, item, _ in performer.clearDownload(item) }
    }

    // MARK: - Actions - Performing

    /// Takes the action on `item`, the download it names, which the row at
    /// `assignment` shows.
    @MainActor func perform(
        on performer: some BrowserDownloadActionPerformer,
        for item: DownloadState,
        matching assignment: BrowserSpaceRuntimeAssignment
    ) {
        step(performer, item, assignment)
    }
}
