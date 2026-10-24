import SwiftUI

private struct BrowserSettingsTabContentKey: EnvironmentKey {
    static let defaultValue: BrowserSettingsTabContent? = nil
}

private struct BrowserSettingsUsesLiveSidebarKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var browserSettingsTabContent: BrowserSettingsTabContent? {
        get { self[BrowserSettingsTabContentKey.self] }
        set { self[BrowserSettingsTabContentKey.self] = newValue }
    }

    /// A docked browser sidebar already shows appearance changes at actual size.
    var browserSettingsUsesLiveSidebar: Bool {
        get { self[BrowserSettingsUsesLiveSidebarKey.self] }
        set { self[BrowserSettingsUsesLiveSidebarKey.self] = newValue }
    }
}

struct BrowserSettingsLiveSpaceSelection {
    let select: @MainActor (UUID) -> Void
}

private struct BrowserSettingsLiveSpaceSelectionKey: EnvironmentKey {
    static let defaultValue: BrowserSettingsLiveSpaceSelection? = nil
}

private struct BrowserSettingsIsTabKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var browserSettingsSelectLiveSpace: BrowserSettingsLiveSpaceSelection? {
        get { self[BrowserSettingsLiveSpaceSelectionKey.self] }
        set { self[BrowserSettingsLiveSpaceSelectionKey.self] = newValue }
    }
    var browserSettingsIsTab: Bool {
        get { self[BrowserSettingsIsTabKey.self] }
        set { self[BrowserSettingsIsTabKey.self] = newValue }
    }
}
