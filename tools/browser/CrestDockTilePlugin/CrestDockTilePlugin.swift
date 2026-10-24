import AppKit

@MainActor
final class CrestDockTilePlugin: NSObject, @preconcurrency NSDockTilePlugIn {
    private var tile: NSDockTile?
    private var appBundle: Bundle?
    private var domain: String?
    private var appearanceObserver: BrowserMacAppIconAppearanceObserver?

    func setDockTile(_ dockTile: NSDockTile?) {
        DistributedNotificationCenter.default().removeObserver(self)
        appearanceObserver?.stop()
        appearanceObserver = nil
        tile = dockTile
        guard dockTile != nil else { return }
        let appURL = Bundle(for: Self.self).bundleURL
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        guard appURL.pathExtension == "app", let bundle = Bundle(url: appURL) else { return }
        appBundle = bundle
        domain =
            bundle.object(forInfoDictionaryKey: BrowserMacAppIconAssets.preferenceDomainKey) as? String
            ?? bundle.bundleIdentifier
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(refresh), name: BrowserMacAppIconAssets.changedNotification,
            object: domain, suspensionBehavior: .deliverImmediately)
        appearanceObserver = BrowserMacAppIconAppearanceObserver { [weak self] in self?.refresh() }
        refresh()
    }

    @objc private func refresh() {
        guard let tile, let appBundle, let domain, let defaults = UserDefaults(suiteName: domain) else { return }
        defaults.synchronize()
        let name = defaults.string(forKey: BrowserMacAppIconAssets.preferenceKey) ?? ""
        if !BrowserMacAppIconAssets.usesSystemAppearance,
            let image = BrowserMacAppIconAssets.image(named: name, in: appBundle)
        {
            // Drawn as the running app draws its own tile.
            let view = BrowserMacDockTileView(frame: CGRect(origin: .zero, size: tile.size))
            view.image = image
            tile.contentView = view
        } else {
            tile.contentView = nil
        }
        tile.display()
    }
}
