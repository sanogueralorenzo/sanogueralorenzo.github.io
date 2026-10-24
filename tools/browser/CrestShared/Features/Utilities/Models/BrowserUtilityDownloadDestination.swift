import Foundation

/// Where a finished download can go from its row.
struct BrowserUtilityDownloadDestination: Hashable, Identifiable, Sendable {
    // MARK: - Static Variables

    static let open = BrowserUtilityDownloadDestination(
        name: "open", title: "Open", symbol: "arrow.up.forward.square",
        delivery: { opener, fileURL in opener.openFile(fileURL) })
    static let revealInFinder = BrowserUtilityDownloadDestination(
        name: "revealInFinder", title: "Show in Finder", symbol: "magnifyingglass", isPrimaryWhenFinished: true,
        delivery: { opener, fileURL in opener.revealFile(fileURL) })
    static let share = BrowserUtilityDownloadDestination(
        name: "share", title: "Share…", symbol: "square.and.arrow.up",
        delivery: { opener, fileURL in opener.shareFile(fileURL) })
    static let files = BrowserUtilityDownloadDestination(
        name: "files", title: "Save to Files…", symbol: "folder.badge.plus",
        delivery: { opener, fileURL in opener.saveFileToFiles(fileURL) })

    /// Every destination.
    static let all: [BrowserUtilityDownloadDestination] = [open, revealInFinder, share, files]

    // MARK: - Variables

    let name: String
    let title: LocalizedStringResource
    let symbol: String

    /// Whether a finished download's row goes here when the person picks the
    /// row itself, where the shell offers this destination.
    let isPrimaryWhenFinished: Bool

    /// Each destination hands the file to a different part of the system,
    /// which the shell's opener reaches.
    private let delivery: @MainActor @Sendable (any BrowserFileDestinationOpener, URL) -> Void

    var id: String { name }

    // MARK: - Initializers

    private init(
        name: String, title: LocalizedStringResource, symbol: String, isPrimaryWhenFinished: Bool = false,
        delivery: @escaping @MainActor @Sendable (any BrowserFileDestinationOpener, URL) -> Void
    ) {
        self.name = name
        self.title = title
        self.symbol = symbol
        self.isPrimaryWhenFinished = isPrimaryWhenFinished
        self.delivery = delivery
    }

    // MARK: - Actions - Lookup

    /// Where a download in `phase` goes when the person picks its row, among
    /// `availableDestinations`: only a finished file has one.
    static func primary(
        for phase: DownloadPhase,
        among availableDestinations: [BrowserUtilityDownloadDestination]
    ) -> BrowserUtilityDownloadDestination? {
        guard phase.isComplete else { return nil }
        return availableDestinations.first(where: \.isPrimaryWhenFinished)
    }

    // MARK: - Actions - Sending

    /// Hands the file at `fileURL` to this destination through `opener`.
    @MainActor func send(_ fileURL: URL, to opener: some BrowserFileDestinationOpener) {
        delivery(opener, fileURL)
    }

    // MARK: - Actions - Identity

    static func == (lhs: BrowserUtilityDownloadDestination, rhs: BrowserUtilityDownloadDestination) -> Bool {
        lhs.name == rhs.name
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
    }
}
