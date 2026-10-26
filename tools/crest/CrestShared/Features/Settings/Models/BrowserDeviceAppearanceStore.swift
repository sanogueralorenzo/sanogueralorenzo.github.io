import Foundation
import Observation
import SwiftUI

// MARK: - Types

/// How tabs look on every Space on this device.
///
/// A model rather than a value, so each view tracks only the choices it draws:
/// a row that reads its border never re-renders while someone drags the hover
/// tint. ``BrowserDeviceAppearanceStore`` keeps the one instance and saves it
/// whenever a choice changes.
@MainActor @Observable
final class BrowserTabAppearance {
    enum Borders: String, Codable, CaseIterable { case selected, pinned, all }
    /// How a tab shows a status its page is in, such as playing sound: as a
    /// badge on its icon, or in place of its icon.
    enum StatusStyle: String, Codable, CaseIterable { case badge, icon }
    var borders: Borders = .selected { didSet { changed() } }
    var outlinesSelectedTabs = false { didSet { changed() } }
    var usesWebsitePinColor = true { didSet { changed() } }
    var dimsUnloadedTabs = true { didSet { changed() } }
    var pinFill: Double = 0 { didSet { changed() } }
    var pinGlow: Double = 0 { didSet { changed() } }
    var hoverFill: Double = 0 { didSet { changed() } }
    var color: BrandColor? { didSet { changed() } }
    var statusStyle: StatusStyle = .badge { didSet { changed() } }
    /// Whether a tab playing sound shows bars across it.
    var showsAudioVisualizer = true { didSet { changed() } }
    /// Called after any choice changes, so its owner can save it.
    @ObservationIgnored var changed: () -> Void = {}

    init() {}

    nonisolated static func intensity(_ value: Double) -> Double {
        value.isFinite ? min(max(value, 0), 1) : 0
    }
}

/// The address field's look on every Space on this device, observed choice by
/// choice as ``BrowserTabAppearance`` is.
@MainActor @Observable
final class BrowserAddressAppearance {
    var fill: Double = 0 { didSet { changed() } }
    var border: Double = 0 { didSet { changed() } }
    var usesAccentWhenEditing = false { didSet { changed() } }
    /// Whether the field grows into the command palette and the palette
    /// shrinks back into it, rather than the palette opening in place.
    var animatesIntoCommandPalette = true { didSet { changed() } }
    var color: BrandColor? { didSet { changed() } }
    /// Called after any choice changes, so its owner can save it.
    @ObservationIgnored var changed: () -> Void = {}

    init() {}
}

extension BrowserTabAppearance: @MainActor Codable {
    private enum CodingKeys: String, CodingKey {
        case borders, outlinesSelectedTabs, usesWebsitePinColor, dimsUnloadedTabs
        case pinFill, pinGlow, hoverFill, color, statusStyle, showsAudioVisualizer
    }

    convenience init(from decoder: Decoder) throws {
        self.init()
        let values = try decoder.container(keyedBy: CodingKeys.self)
        borders = (try? values.decode(Borders.self, forKey: .borders)) ?? .selected
        outlinesSelectedTabs = (try? values.decode(Bool.self, forKey: .outlinesSelectedTabs)) ?? false
        usesWebsitePinColor = (try? values.decode(Bool.self, forKey: .usesWebsitePinColor)) ?? true
        dimsUnloadedTabs = (try? values.decode(Bool.self, forKey: .dimsUnloadedTabs)) ?? true
        pinFill = Self.intensity((try? values.decode(Double.self, forKey: .pinFill)) ?? 0)
        pinGlow = Self.intensity((try? values.decode(Double.self, forKey: .pinGlow)) ?? 0)
        hoverFill = Self.intensity((try? values.decode(Double.self, forKey: .hoverFill)) ?? 0)
        color = try? values.decode(BrandColor.self, forKey: .color)
        statusStyle = (try? values.decode(StatusStyle.self, forKey: .statusStyle)) ?? .badge
        showsAudioVisualizer = (try? values.decode(Bool.self, forKey: .showsAudioVisualizer)) ?? true
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(borders, forKey: .borders)
        try values.encode(outlinesSelectedTabs, forKey: .outlinesSelectedTabs)
        try values.encode(usesWebsitePinColor, forKey: .usesWebsitePinColor)
        try values.encode(dimsUnloadedTabs, forKey: .dimsUnloadedTabs)
        try values.encode(pinFill, forKey: .pinFill)
        try values.encode(pinGlow, forKey: .pinGlow)
        try values.encode(hoverFill, forKey: .hoverFill)
        try values.encodeIfPresent(color, forKey: .color)
        try values.encode(statusStyle, forKey: .statusStyle)
        try values.encode(showsAudioVisualizer, forKey: .showsAudioVisualizer)
    }
}

extension BrowserAddressAppearance: @MainActor Codable {
    private enum CodingKeys: String, CodingKey {
        case fill, border, usesAccentWhenEditing, animatesIntoCommandPalette, color
    }

    convenience init(from decoder: Decoder) throws {
        self.init()
        let values = try decoder.container(keyedBy: CodingKeys.self)
        fill = BrowserTabAppearance.intensity((try? values.decode(Double.self, forKey: .fill)) ?? 0)
        border = BrowserTabAppearance.intensity((try? values.decode(Double.self, forKey: .border)) ?? 0)
        usesAccentWhenEditing = (try? values.decode(Bool.self, forKey: .usesAccentWhenEditing)) ?? false
        animatesIntoCommandPalette =
            (try? values.decode(Bool.self, forKey: .animatesIntoCommandPalette)) ?? true
        color = try? values.decode(BrandColor.self, forKey: .color)
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(fill, forKey: .fill)
        try values.encode(border, forKey: .border)
        try values.encode(usesAccentWhenEditing, forKey: .usesAccentWhenEditing)
        try values.encode(animatesIntoCommandPalette, forKey: .animatesIntoCommandPalette)
        try values.encodeIfPresent(color, forKey: .color)
    }
}

/// Local presentation preferences never enter a Space record or CloudKit payload.
/// Decode once; Observation invalidates only views reading the changed value.
///
/// Views read the choices they draw from here, never with `@AppStorage`: each
/// write to these defaults makes every `@AppStorage` view over them re-check
/// its value, and a sidebar would hold hundreds. For the same reason the store
/// keeps every choice in memory and writes them out once they settle, not on
/// every step of a drag.
@MainActor @Observable
final class BrowserDeviceAppearanceStore {
    // MARK: - Static Variables

    static let shared = BrowserDeviceAppearanceStore(
        defaults: BrowserFolderAppearancePreference.defaults, chrome: BrowserChromeAppearancePreference.defaults)
    static let tabsKey = "crest.appearance.tabs"
    static let addressKey = "crest.appearance.address"
    static let cornerRadiusKey = "crest.appearance.cornerRadius"
    static let surfaceMaterialKey = "crest.appearance.surfaceMaterial"
    static let modeKey = "crest.appearance.mode"
    static let darkSpaceDimmingKey = "crest.appearance.darkSpaceDimming"
    static let spaceIconSizingKey = "crest.appearance.spaceIconSizing"
    static let spaceIconScaleKey = "crest.appearance.spaceIconScale"
    static let sidebarRevealWidthKey = "crest.appearance.sidebar-reveal-width"
    static let maximumCornerRadius: Double = 40
    /// How long the choices stay still before the store writes them out.
    static let settleDelay = Duration.milliseconds(300)

    // MARK: - Variables

    var cornerRadius: Double {
        didSet { saveSoon() }
    }
    var sidebarCornerRadius: Double {
        cornerRadius.isFinite
            ? min(max(cornerRadius, 0), Self.maximumCornerRadius) : BrowserLookAndFeelDefaults.cornerRadius
    }
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let chrome: UserDefaults
    /// The write waiting for the choices to settle.
    @ObservationIgnored private var pendingSave: Task<Void, Never>?
    /// How wide the frame around every page is, in points; zero runs pages to
    /// the window's edges.
    var windowBorderWidth: Double {
        didSet {
            isBorderless = BrowserChromeAppearance(borderWidth: windowBorderWidth).borderless
            saveSoon()
        }
    }
    /// Whether pages run to the window's edges. A view that only asks this
    /// reads it rather than the width, so a drag across the width leaves it be.
    private(set) var isBorderless: Bool
    /// Whether the sidebar stands on the window's right.
    var sidebarOnRight: Bool {
        didSet { saveSoon() }
    }
    /// How wide, in points, the strip along the window's edge is that shows a
    /// hidden sidebar when the pointer rests on it. Only the Mac has one.
    var sidebarRevealWidth: Double {
        didSet { saveSoon() }
    }
    /// How tabs look. Replaced only to reset it; otherwise its choices change
    /// in place, each observed on its own. A binding to one choice assigns the
    /// same instance back, which is no change.
    var tabs: BrowserTabAppearance {
        didSet {
            guard tabs !== oldValue else { return }
            observeChanges()
            saveSoon()
        }
    }
    /// How the address field looks, kept as ``tabs`` is.
    var address: BrowserAddressAppearance {
        didSet {
            guard address !== oldValue else { return }
            observeChanges()
            saveSoon()
        }
    }
    /// The material the sidebar's layers are drawn with, stored by name.
    var surfaceMaterial: CrestSurfaceMaterial {
        didSet { saveSoon() }
    }
    /// Whether windows draw light, dark, or as the system does, stored by name.
    var mode: BrowserAppearanceMode {
        didSet { saveSoon() }
    }
    /// How far a dark appearance dims each Space's colors toward charcoal,
    /// from 0, as chosen, to 1.
    var darkSpaceDimming: Double {
        didSet {
            dimsSpaceColors = Self.dims(in: shownColorScheme, by: darkSpaceDimming)
            saveSoon()
        }
    }
    /// Whether the Space switcher fits its icons to the sidebar or draws them
    /// at ``spaceIconScale``, stored by name.
    var spaceIconSizing: BrowserSpaceIconSizing {
        didSet { saveSoon() }
    }
    /// The size the Space switcher draws its icons at when it does not fit
    /// them, as a fraction of their usual size.
    var spaceIconScale: Double {
        didSet { saveSoon() }
    }
    /// The size tabs, pins and folders are drawn at, as a fraction of their
    /// usual size.
    var tabScale: Double {
        didSet { saveSoon() }
    }
    /// How many pins a row holds at most; zero balances the rows.
    var pinColumns: Int {
        didSet { saveSoon() }
    }
    /// Whether a short last row of pins stretches across the sidebar instead
    /// of leaving empty cells.
    var pinsFillRow: Bool {
        didSet { saveSoon() }
    }
    /// Whether folders keep their highlight when the pointer is elsewhere and
    /// none of their tabs is selected.
    var foldersAlwaysVisible: Bool {
        didSet { saveSoon() }
    }
    /// Whether folder headers show how many tabs they hold.
    var foldersShowTabCounts: Bool {
        didSet { saveSoon() }
    }
    /// Whether folders draw a border in their color.
    var foldersShowBorders: Bool {
        didSet { saveSoon() }
    }
    /// Whether a folder with a custom icon or emoji shows it in place of the
    /// folder artwork.
    var foldersIconOnly: Bool {
        didSet { saveSoon() }
    }
    /// Whether folder titles take the folder's color.
    var foldersTintTitle: Bool {
        didSet { saveSoon() }
    }
    /// The scheme the windows draw in now, as the platform reports it once
    /// ``mode`` and the system's own appearance are applied.
    var shownColorScheme = ColorScheme.light {
        didSet { dimsSpaceColors = Self.dims(in: shownColorScheme, by: darkSpaceDimming) }
    }
    /// Whether the windows dim Space colors now, as a dark scheme with some
    /// dimming does. A view that only asks this tracks it rather than the
    /// dimming, so a drag of the dimming leaves it be.
    private(set) var dimsSpaceColors = false

    // MARK: - Initializers

    /// A store over `defaults`, which keeps the window's frame and sidebar
    /// side in `chrome` where those live apart from the rest.
    init(defaults: UserDefaults, chrome: UserDefaults? = nil) {
        self.defaults = defaults
        let chrome = chrome ?? defaults
        self.chrome = chrome
        let borderWidth =
            chrome.object(forKey: BrowserChromeAppearancePreference.borderWidthKey) as? Double
            ?? BrowserLookAndFeelDefaults.windowBorderWidth
        windowBorderWidth = borderWidth
        isBorderless = BrowserChromeAppearance(borderWidth: borderWidth).borderless
        sidebarOnRight = chrome.bool(forKey: BrowserChromeAppearancePreference.sidebarOnRightKey)
        sidebarRevealWidth =
            chrome.object(forKey: Self.sidebarRevealWidthKey) as? Double
            ?? Double(BrowserCollapsedSidebarRevealMetrics.pointer.width)
        if defaults.object(forKey: Self.cornerRadiusKey) != nil {
            cornerRadius = defaults.double(forKey: Self.cornerRadiusKey)
        } else {
            let legacy =
                defaults.data(forKey: Self.tabsKey).flatMap {
                    try? JSONSerialization.jsonObject(with: $0) as? [String: Any]
                }?["cornerRadius"] as? Double
            let migratedRadius =
                legacy == 24 ? Self.maximumCornerRadius : (legacy ?? BrowserLookAndFeelDefaults.cornerRadius)
            cornerRadius = migratedRadius
            defaults.set(
                migratedRadius.isFinite
                    ? min(max(migratedRadius, 0), Self.maximumCornerRadius) : BrowserLookAndFeelDefaults.cornerRadius,
                forKey: Self.cornerRadiusKey)
        }
        tabs =
            defaults.data(forKey: Self.tabsKey).flatMap {
                try? JSONDecoder().decode(BrowserTabAppearance.self, from: $0)
            } ?? .init()
        address =
            defaults.data(forKey: Self.addressKey).flatMap {
                try? JSONDecoder().decode(BrowserAddressAppearance.self, from: $0)
            } ?? .init()
        surfaceMaterial =
            CrestSurfaceMaterial.named(defaults.string(forKey: Self.surfaceMaterialKey))
            ?? BrowserLookAndFeelDefaults.surfaceMaterial
        mode =
            BrowserAppearanceMode.named(defaults.string(forKey: Self.modeKey))
            ?? BrowserLookAndFeelDefaults.appearanceMode
        darkSpaceDimming =
            (defaults.object(forKey: Self.darkSpaceDimmingKey) as? Double).flatMap {
                $0.isFinite ? min(max($0, 0), 1) : nil
            } ?? BrowserLookAndFeelDefaults.darkSpaceDimming
        spaceIconSizing =
            BrowserSpaceIconSizing.named(defaults.string(forKey: Self.spaceIconSizingKey))
            ?? BrowserLookAndFeelDefaults.spaceIconSizing
        spaceIconScale =
            (defaults.object(forKey: Self.spaceIconScaleKey) as? Double).map {
                Double(BrowserSpaceIconSizing.clamped($0))
            } ?? BrowserLookAndFeelDefaults.spaceIconScale
        tabScale =
            (defaults.object(forKey: BrowserSidebarDensityPreference.scaleKey) as? Double).flatMap {
                $0.isFinite ? $0 : nil
            } ?? BrowserLookAndFeelDefaults.tabScale
        pinColumns =
            defaults.object(forKey: BrowserSidebarDensityPreference.pinColumnsKey) as? Int
            ?? BrowserLookAndFeelDefaults.pinColumns
        pinsFillRow =
            defaults.object(forKey: BrowserSidebarDensityPreference.pinsFillRowKey) as? Bool
            ?? BrowserLookAndFeelDefaults.pinsFillRow
        foldersAlwaysVisible =
            defaults.object(forKey: BrowserFolderAppearancePreference.alwaysVisibleKey) as? Bool
            ?? BrowserLookAndFeelDefaults.foldersAlwaysVisible
        foldersShowTabCounts =
            defaults.object(forKey: BrowserFolderAppearancePreference.showsTabCountsKey) as? Bool
            ?? BrowserLookAndFeelDefaults.foldersShowTabCounts
        foldersShowBorders =
            defaults.object(forKey: BrowserFolderAppearancePreference.showsBordersKey) as? Bool
            ?? BrowserLookAndFeelDefaults.foldersShowBorders
        foldersIconOnly =
            defaults.object(forKey: BrowserFolderAppearancePreference.iconOnlyKey) as? Bool
            ?? BrowserLookAndFeelDefaults.foldersIconOnly
        foldersTintTitle =
            defaults.object(forKey: BrowserFolderAppearancePreference.tintsTitleKey) as? Bool
            ?? BrowserLookAndFeelDefaults.foldersTintTitle
        dimsSpaceColors = Self.dims(in: shownColorScheme, by: darkSpaceDimming)
        observeChanges()
        // A choice made just before the app quits or steps aside, or leaves
        // for the background where it may never come back, is written at once.
        for notification in Self.leavingNotifications {
            NotificationCenter.default.addObserver(forName: notification, object: nil, queue: .main) {
                [weak self] _ in
                MainActor.assumeIsolated { self?.saveNow() }
            }
        }
    }

    // MARK: - Actions - Space Colors

    /// Whether a window in `colorScheme` dims Space colors `dimming` of the way.
    private static func dims(in colorScheme: ColorScheme, by dimming: Double) -> Bool {
        colorScheme == .dark && dimming > 0
    }

    // MARK: - Actions - Saving

    /// Writes every choice that changed now, rather than once they settle.
    func saveNow() {
        pendingSave?.cancel()
        pendingSave = nil
        write(sidebarCornerRadius, forKey: Self.cornerRadiusKey, in: defaults)
        write(try? JSONEncoder().encode(tabs), forKey: Self.tabsKey, in: defaults)
        write(try? JSONEncoder().encode(address), forKey: Self.addressKey, in: defaults)
        write(surfaceMaterial.name, forKey: Self.surfaceMaterialKey, in: defaults)
        write(mode.name, forKey: Self.modeKey, in: defaults)
        write(darkSpaceDimming, forKey: Self.darkSpaceDimmingKey, in: defaults)
        write(spaceIconSizing.name, forKey: Self.spaceIconSizingKey, in: defaults)
        write(spaceIconScale, forKey: Self.spaceIconScaleKey, in: defaults)
        write(tabScale, forKey: BrowserSidebarDensityPreference.scaleKey, in: defaults)
        write(pinColumns, forKey: BrowserSidebarDensityPreference.pinColumnsKey, in: defaults)
        write(pinsFillRow, forKey: BrowserSidebarDensityPreference.pinsFillRowKey, in: defaults)
        write(foldersAlwaysVisible, forKey: BrowserFolderAppearancePreference.alwaysVisibleKey, in: defaults)
        write(foldersShowTabCounts, forKey: BrowserFolderAppearancePreference.showsTabCountsKey, in: defaults)
        write(foldersShowBorders, forKey: BrowserFolderAppearancePreference.showsBordersKey, in: defaults)
        write(foldersIconOnly, forKey: BrowserFolderAppearancePreference.iconOnlyKey, in: defaults)
        write(foldersTintTitle, forKey: BrowserFolderAppearancePreference.tintsTitleKey, in: defaults)
        write(windowBorderWidth, forKey: BrowserChromeAppearancePreference.borderWidthKey, in: chrome)
        write(sidebarOnRight, forKey: BrowserChromeAppearancePreference.sidebarOnRightKey, in: chrome)
        write(sidebarRevealWidth, forKey: Self.sidebarRevealWidthKey, in: chrome)
    }

    /// Writes the choices once they have stayed still for ``settleDelay``.
    private func saveSoon() {
        pendingSave?.cancel()
        pendingSave = Task { [weak self] in
            try? await Task.sleep(for: Self.settleDelay)
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    /// Writes `value` unless the defaults hold it already, so a write that
    /// changes nothing never makes their `@AppStorage` views re-check.
    private func write(_ value: Any?, forKey key: String, in defaults: UserDefaults) {
        guard let value, (defaults.object(forKey: key) as? NSObject)?.isEqual(value) != true else { return }
        defaults.set(value, forKey: key)
    }

    /// Saves the tab and address appearance once a choice in one of them
    /// changes.
    private func observeChanges() {
        tabs.changed = { [weak self] in self?.saveSoon() }
        address.changed = { [weak self] in self?.saveSoon() }
    }

    #if os(macOS)
        private static var leavingNotifications: [Notification.Name] {
            [NSApplication.willTerminateNotification, NSApplication.didResignActiveNotification]
        }
    #else
        private static var leavingNotifications: [Notification.Name] { [UIApplication.didEnterBackgroundNotification] }
    #endif
}
