import Dispatch
import Observation
import UIKit
import UniformTypeIdentifiers
import WebKit

/// Where an exported page or a finished download goes on a device without a
/// Finder: the share sheet or the Files picker.
struct MobileBrowserFileExportDestination: Hashable, Identifiable, Sendable {
    // MARK: - Static Variables

    static let share = MobileBrowserFileExportDestination(download: .share)
    static let files = MobileBrowserFileExportDestination(download: .files)

    /// Every destination, in menu order.
    static let all: [MobileBrowserFileExportDestination] = [share, files]

    // MARK: - Variables

    /// The download row destination that exports this way, whose title and
    /// symbol this destination shares, and which presents its own system
    /// controller.
    let download: BrowserUtilityDownloadDestination

    var name: String { download.name }
    var title: LocalizedStringResource { download.title }
    var symbol: String { download.symbol }
    var id: String { name }

    // MARK: - Initializers

    private init(download: BrowserUtilityDownloadDestination) {
        self.download = download
    }

    // MARK: - Actions - Lookup

    /// The export a download row's destination asks for, if it is one.
    static func exporting(_ download: BrowserUtilityDownloadDestination) -> MobileBrowserFileExportDestination? {
        all.first { $0.download == download }
    }

    // MARK: - Actions - Identity

    static func == (lhs: MobileBrowserFileExportDestination, rhs: MobileBrowserFileExportDestination) -> Bool {
        lhs.name == rhs.name
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
    }
}
