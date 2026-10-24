import Observation
import SwiftUI

@Observable @MainActor
final class BrowserSettingsTabState {
    var navigation = BrowserSettingsNavigationState()
    var featureFilter = BrowserWebKitFeatureFlagFilter()
    /// The page shown for a Space, kept as the selection moves between Spaces.
    var spaceTab = BrowserSpaceSettingsTab.appearance
    /// The Crest Studio step shown on a Space's Appearance page.
    var forgeStep = BrowserCrestStudioStep.shape
    /// Whether the sidebar's Spaces can be dragged into a new order.
    var isArrangingSpaces = false
    /// The Space whose name is waiting to be put into editing.
    var renameSpaceID: UUID?
    let sidebarScroll = BrowserNativeScrollState()
    private(set) var consumedRouteRevision = 0
    @ObservationIgnored private var scrollStates: [String: BrowserNativeScrollState] = [:]
    @ObservationIgnored private var shortcuts: BrowserShortcutSettingsModel?

    func retainShortcuts(_ initial: BrowserShortcutSettingsModel) -> BrowserShortcutSettingsModel {
        if let shortcuts { return shortcuts }
        shortcuts = initial
        return initial
    }

    func scroll(for destination: BrowserSettingsDestination) -> BrowserNativeScrollState {
        scroll(forKey: destination.name)
    }

    /// The scroll position of one page, by the key the page names itself with.
    func scroll(forKey key: String) -> BrowserNativeScrollState {
        if let state = scrollStates[key] { return state }
        let state = BrowserNativeScrollState()
        scrollStates[key] = state
        return state
    }

    /// Shows a Space's page, asking it for `intent` on arrival.
    func showSpace(_ id: UUID, tab: BrowserSpaceSettingsTab, intent: BrowserSettingsSpaceIntent = .none) {
        navigation.selection = .space(id)
        spaceTab = tab
        if intent != .none { renameSpaceID = id }
        // A new Space starts by choosing the template it is made from.
        if intent == .newSpace { forgeStep = .start }
    }

    func applyExternalRoute(
        _ request: any BrowserSettingsRequest,
        spaceID: UUID?,
        searchText: String?,
        revision: Int
    ) {
        guard revision > consumedRouteRevision else { return }
        consumedRouteRevision = revision
        if let searchText { navigation.searchText = searchText }
        request.apply(to: self, spaceID: spaceID)
    }
}

private struct BrowserSettingsTabStateKey: EnvironmentKey {
    static let defaultValue: BrowserSettingsTabState? = nil
}

private struct BrowserSettingsScrollKeyKey: EnvironmentKey {
    static let defaultValue: String? = nil
}

private struct BrowserSettingsColumnWidthKey: EnvironmentKey {
    static let defaultValue: CGFloat? = nil
}

extension EnvironmentValues {
    var browserSettingsTabState: BrowserSettingsTabState? {
        get { self[BrowserSettingsTabStateKey.self] }
        set { self[BrowserSettingsTabStateKey.self] = newValue }
    }

    /// The key a settings form keeps its scroll position under, where one
    /// destination's form appears on more than one page.
    var browserSettingsScrollKey: String? {
        get { self[BrowserSettingsScrollKeyKey.self] }
        set { self[BrowserSettingsScrollKeyKey.self] = newValue }
    }

    /// The width of a page's column of rows, where it isn't the usual.
    var browserSettingsColumnWidth: CGFloat? {
        get { self[BrowserSettingsColumnWidthKey.self] }
        set { self[BrowserSettingsColumnWidthKey.self] = newValue }
    }
}
