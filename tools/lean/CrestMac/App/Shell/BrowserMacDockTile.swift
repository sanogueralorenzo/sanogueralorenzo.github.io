import AppKit
import Observation

/// The application's Dock tile, which the shell owns for either product: the
/// app icon the person picked, and while downloads are in progress, how many
/// and how far along. The engine that owns the process draws nothing there.
///
/// The icon choice is kept in `defaults`, where the Dock tile plug-in reads it
/// while the app is not running and draws it the same way. Clear and Tinted
/// icons belong to Icon Services: passing their rasterized preview back would
/// lose the Dock's native resolution and treatment, so the tile then draws
/// nothing of its own and shows only the count of downloads.
@MainActor
final class BrowserMacDockTile {
    // MARK: - Static Variables

    /// The application's one Dock tile.
    static let shared = BrowserMacDockTile()

    // MARK: - Types

    /// What the tile shows, which it redraws only when it changes.
    private struct Face: Equatable {
        let drawsIcon: Bool
        let badge: String?
        let progress: Double?
    }

    // MARK: - Variables

    private let view = BrowserMacDockTileView()
    /// The read model whose downloads the tile shows.
    private weak var state: CoreState?
    /// The face as last drawn.
    private var face: Face?

    // MARK: - Initializers

    private init() {}

    // MARK: - Actions - Starting

    /// Draws the picked icon, and from now on again whenever the choice, the
    /// system's appearance or `core`'s downloads change.
    func start(following core: CrestCore) {
        guard state == nil else { return }
        state = core.state
        view.image = NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath)
        followDownloads()
    }

    // MARK: - Actions - Downloads

    /// Redraws the tile now and whenever the downloads change.
    private func followDownloads() {
        withObservationTracking {
            redraw()
        } onChange: { [weak self] in
            Task { @MainActor in self?.followDownloads() }
        }
    }

    /// Draws the downloads in progress: their count as the badge, and a bar
    /// for how far along they are once every one knows its size. The tile
    /// draws the icon itself only when it has a palette icon or a bar to show,
    /// and takes the tile back if anything else drew there.
    private func redraw() {
        let live = state?.downloads.filter(\.phase.isLive) ?? []
        let progress = Self.progress(of: live)
        let next = Face(
            drawsIcon: progress != nil,
            badge: live.isEmpty ? nil : live.count.formatted(), progress: progress)
        let tile = NSApp.dockTile
        let ownsTile = next.drawsIcon ? tile.contentView === view : tile.contentView == nil
        guard next != face || !ownsTile else { return }
        face = next
        view.frame = NSRect(origin: .zero, size: tile.size)
        view.progress = next.progress
        tile.contentView = next.drawsIcon ? view : nil
        tile.badgeLabel = next.badge
        tile.display()
    }

    /// How far the transferring downloads among `live` are together, to the
    /// nearest hundredth, or nil while none transfers or one does not know
    /// its size yet.
    private static func progress(of live: [DownloadState]) -> Double? {
        let transferring = live.filter(\.phase.isTransferring).map(\.telemetry)
        let sizes = transferring.compactMap(\.totalBytes)
        let total = sizes.reduce(0, +)
        guard !transferring.isEmpty, sizes.count == transferring.count, total > 0 else { return nil }
        let received = transferring.map(\.bytesReceived).reduce(0, +)
        return (Double(received) / Double(total) * 100).rounded() / 100
    }
}
