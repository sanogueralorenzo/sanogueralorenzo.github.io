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

    /// Where the icon choice is kept. A composition whose Dock plug-in reads
    /// another domain names it before the tile starts.
    var defaults = BrowserFolderAppearancePreference.defaults
    private let view = BrowserMacDockTileView()
    /// The read model whose downloads the tile shows.
    private weak var state: CoreState?
    private var appearanceObserver: BrowserMacAppIconAppearanceObserver?
    /// The face as last drawn.
    private var face: Face?

    /// Whether the person picked a palette icon rather than Crest's own.
    private var hasPaletteIcon: Bool {
        !(defaults.string(forKey: BrowserMacAppIconAssets.preferenceKey) ?? "").isEmpty
    }

    // MARK: - Initializers

    private init() {}

    // MARK: - Actions - Starting

    /// Draws the picked icon, and from now on again whenever the choice, the
    /// system's appearance or `core`'s downloads change.
    func start(following core: CrestCore) {
        guard state == nil else { return }
        state = core.state
        appearanceObserver = BrowserMacAppIconAppearanceObserver { [weak self] in self?.refreshIcon() }
        refreshIcon()
        followDownloads()
    }

    // MARK: - Actions - Icon

    /// Picks the palette icon `name`, or Crest's own icon for an empty name,
    /// and tells the Dock tile plug-in. False when there is no such icon.
    @discardableResult
    func select(_ name: String) -> Bool {
        guard name.isEmpty || BrowserMacAppIconAssets.image(named: name, in: .main) != nil else { return false }
        defaults.set(name, forKey: BrowserMacAppIconAssets.preferenceKey)
        defaults.synchronize()
        refreshIcon()
        let domain =
            Bundle.main.object(forInfoDictionaryKey: BrowserMacAppIconAssets.preferenceDomainKey) as? String
            ?? Bundle.main.bundleIdentifier
        DistributedNotificationCenter.default().postNotificationName(
            BrowserMacAppIconAssets.changedNotification, object: domain, userInfo: nil, deliverImmediately: true)
        return true
    }

    /// Makes the picked icon the application's, which the About panel and
    /// notifications show too, and redraws the tile.
    private func refreshIcon() {
        let name = defaults.string(forKey: BrowserMacAppIconAssets.preferenceKey) ?? ""
        NSApp.applicationIconImage =
            BrowserMacAppIconAssets.usesSystemAppearance ? nil : BrowserMacAppIconAssets.image(named: name, in: .main)
        view.image = NSApp.applicationIconImage
        face = nil
        redraw()
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
        let systemRendered = BrowserMacAppIconAssets.usesSystemAppearance
        let progress = systemRendered ? nil : Self.progress(of: live)
        let next = Face(
            drawsIcon: !systemRendered && (hasPaletteIcon || progress != nil),
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
