import Foundation
import Observation
import SwiftUI

struct BrowserTabAppearance: Codable, Equatable, Sendable {
    enum Borders: String, Codable, CaseIterable { case selected, pinned, all }
    /// How a tab shows a status its page is in, such as playing sound: as a
    /// badge on its icon, or in place of its icon.
    enum StatusStyle: String, Codable, CaseIterable { case badge, icon }
    var borders: Borders = .selected
    var outlinesSelectedTabs = false
    var usesWebsitePinColor = true
    var dimsUnloadedTabs = true
    var pinFill: Double = 0
    var pinGlow: Double = 0
    var hoverFill: Double = 0
    var color: BrandColor?
    var statusStyle: StatusStyle = .badge
    /// Whether a tab playing sound shows bars across it.
    var showsAudioVisualizer = true

    static func intensity(_ value: Double) -> Double {
        value.isFinite ? min(max(value, 0), 1) : 0
    }
}

struct BrowserAddressAppearance: Codable, Equatable, Sendable {
    var fill: Double = 0
    var border: Double = 0
    var usesAccentWhenEditing = false
    /// Whether the field grows into the command palette and the palette
    /// shrinks back into it, rather than the palette opening in place.
    var animatesIntoCommandPalette = true
    var color: BrandColor?
}

extension BrowserTabAppearance {
    private enum CodingKeys: String, CodingKey {
        case borders, outlinesSelectedTabs, usesWebsitePinColor, dimsUnloadedTabs
        case pinFill, pinGlow, hoverFill, color, statusStyle, showsAudioVisualizer
    }

    init(from decoder: Decoder) throws {
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
}

extension BrowserAddressAppearance {
    private enum CodingKeys: String, CodingKey {
        case fill, border, usesAccentWhenEditing, animatesIntoCommandPalette, color
    }

    init(from decoder: Decoder) throws {
        self.init()
        let values = try decoder.container(keyedBy: CodingKeys.self)
        fill = BrowserTabAppearance.intensity((try? values.decode(Double.self, forKey: .fill)) ?? 0)
        border = BrowserTabAppearance.intensity((try? values.decode(Double.self, forKey: .border)) ?? 0)
        usesAccentWhenEditing = (try? values.decode(Bool.self, forKey: .usesAccentWhenEditing)) ?? false
        animatesIntoCommandPalette =
            (try? values.decode(Bool.self, forKey: .animatesIntoCommandPalette)) ?? true
        color = try? values.decode(BrandColor.self, forKey: .color)
    }
}

/// Local presentation preferences never enter a Space record or CloudKit payload.
/// Decode once; Observation invalidates only views reading the changed value.
@MainActor @Observable
final class BrowserDeviceAppearanceStore {
    static let shared = BrowserDeviceAppearanceStore(defaults: BrowserFolderAppearancePreference.defaults)
    static let tabsKey = "crest.appearance.tabs"
    static let addressKey = "crest.appearance.address"
    static let cornerRadiusKey = "crest.appearance.cornerRadius"
    static let surfaceMaterialKey = "crest.appearance.surfaceMaterial"
    static let modeKey = "crest.appearance.mode"
    static let darkSpaceDimmingKey = "crest.appearance.darkSpaceDimming"
    static let spaceIconSizingKey = "crest.appearance.spaceIconSizing"
    static let spaceIconScaleKey = "crest.appearance.spaceIconScale"
    static let maximumCornerRadius: Double = 40
    var cornerRadius: Double {
        didSet { defaults.set(sidebarCornerRadius, forKey: Self.cornerRadiusKey) }
    }
    var sidebarCornerRadius: Double {
        cornerRadius.isFinite
            ? min(max(cornerRadius, 0), Self.maximumCornerRadius) : BrowserLookAndFeelDefaults.cornerRadius
    }
    @ObservationIgnored private let defaults: UserDefaults
    var tabs: BrowserTabAppearance { didSet { save(tabs, key: Self.tabsKey) } }
    var address: BrowserAddressAppearance { didSet { save(address, key: Self.addressKey) } }
    /// The material the sidebar's layers are drawn with, stored by name.
    var surfaceMaterial: CrestSurfaceMaterial {
        didSet { defaults.set(surfaceMaterial.name, forKey: Self.surfaceMaterialKey) }
    }
    /// Whether windows draw light, dark, or as the system does, stored by name.
    var mode: BrowserAppearanceMode {
        didSet { defaults.set(mode.name, forKey: Self.modeKey) }
    }
    /// How far a dark appearance dims each Space's colors toward charcoal,
    /// from 0, as chosen, to 1.
    var darkSpaceDimming: Double {
        didSet { defaults.set(darkSpaceDimming, forKey: Self.darkSpaceDimmingKey) }
    }
    /// Whether the Space switcher fits its icons to the sidebar or draws them
    /// at ``spaceIconScale``, stored by name.
    var spaceIconSizing: BrowserSpaceIconSizing {
        didSet { defaults.set(spaceIconSizing.name, forKey: Self.spaceIconSizingKey) }
    }
    /// The size the Space switcher draws its icons at when it does not fit
    /// them, as a fraction of their usual size.
    var spaceIconScale: Double {
        didSet { defaults.set(spaceIconScale, forKey: Self.spaceIconScaleKey) }
    }
    /// The scheme the windows draw in now, as the platform reports it once
    /// ``mode`` and the system's own appearance are applied.
    var shownColorScheme = ColorScheme.light

    init(defaults: UserDefaults) {
        self.defaults = defaults
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
    }

    private func save(_ value: some Encodable, key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: key)
    }
}
