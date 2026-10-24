import AppKit

/// Shared by Crest and its Dock tile plug-in. Palette choices never write system appearance preferences.
enum BrowserMacAppIconAssets {
    static let preferenceKey = "crest.appearance.appIcon"
    static let preferenceDomainKey = "CrestAppIconPreferenceDomain"
    static let changedNotification = Notification.Name("com.pauldavis.crest.appIconChanged")
    static let systemAppearanceKey = "AppleIconAppearanceTheme"

    static var usesSystemAppearance: Bool {
        let theme = UserDefaults.standard.string(forKey: systemAppearanceKey)?.lowercased() ?? ""
        return theme.contains("clear") || theme.contains("tinted") || theme.contains("mono")
    }

    @MainActor
    static func image(named name: String, in bundle: Bundle) -> NSImage? {
        guard name.range(of: "^Crest[A-Z][a-z]{1,20}$", options: .regularExpression) != nil,
            let light = bundle.image(forResource: NSImage.Name(name + "DockLight"))
        else { return nil }
        let theme = UserDefaults.standard.string(forKey: systemAppearanceKey)?.lowercased() ?? ""
        // All palette variants deliberately share their monochrome layers. Let Icon
        // Services render Clear and Tinted, including the system's glass treatment.
        if usesSystemAppearance {
            return NSWorkspace.shared.icon(forFile: bundle.bundlePath)
        }
        let dark =
            theme.contains("dark")
            || (!theme.contains("light") && theme.isEmpty
                && NSApp?.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua)
        // Both exports contain the same macOS margin and explicit 1x/2x images.
        // Use the finished artwork directly in the Dock and settings selector.
        return dark ? bundle.image(forResource: NSImage.Name(name + "DockDark")) : light
    }
}

/// UserDefaults observes the icon preference across processes; the theme notification
/// also covers automatic light/dark transitions. Each owner explicitly stops observing.
@MainActor
final class BrowserMacAppIconAppearanceObserver: NSObject {
    private let changed: () -> Void
    private var isObserving = true

    init(changed: @escaping () -> Void) {
        self.changed = changed
        super.init()
        UserDefaults.standard.addObserver(
            self, forKeyPath: BrowserMacAppIconAssets.systemAppearanceKey,
            options: [], context: nil)
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(themeChanged),
            name: Notification.Name("AppleInterfaceThemeChangedNotification"), object: nil,
            suspensionBehavior: .deliverImmediately)
    }

    func stop() {
        guard isObserving else { return }
        isObserving = false
        UserDefaults.standard.removeObserver(self, forKeyPath: BrowserMacAppIconAssets.systemAppearanceKey)
        DistributedNotificationCenter.default().removeObserver(self)
    }

    override nonisolated func observeValue(
        forKeyPath keyPath: String?, of object: Any?,
        change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?
    ) {
        Task { @MainActor [weak self] in self?.changed() }
    }

    @objc nonisolated private func themeChanged() {
        Task { @MainActor [weak self] in self?.changed() }
    }
}
