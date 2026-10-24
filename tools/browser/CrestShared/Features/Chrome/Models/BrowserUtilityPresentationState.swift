import Foundation
import Observation
import SwiftUI

@Observable
@MainActor
final class BrowserUtilityPresentationState {
    static let selectedSurfaceDefaultsKey = "browser.utility.selected-surface"

    private(set) var surface: BrowserUtilitySurface? {
        get { observed(\.surfaceStorage, as: \.surface) }
        set { publish(newValue, into: \.surfaceStorage, as: \.surface) }
    }
    @ObservationIgnored private var surfaceStorage: BrowserUtilitySurface?
    private(set) var isSwitcherExpanded: Bool {
        get { observed(\.isSwitcherExpandedStorage, as: \.isSwitcherExpanded) }
        set { publish(newValue, into: \.isSwitcherExpandedStorage, as: \.isSwitcherExpanded) }
    }
    @ObservationIgnored private var isSwitcherExpandedStorage = false
    private(set) var isSiteControlPresented: Bool {
        get { observed(\.isSiteControlPresentedStorage, as: \.isSiteControlPresented) }
        set { publish(newValue, into: \.isSiteControlPresentedStorage, as: \.isSiteControlPresented) }
    }
    @ObservationIgnored private var isSiteControlPresentedStorage = false
    private(set) var isSiteControlContextMenuPresented: Bool {
        get { observed(\.isSiteControlContextMenuPresentedStorage, as: \.isSiteControlContextMenuPresented) }
        set {
            publish(newValue, into: \.isSiteControlContextMenuPresentedStorage, as: \.isSiteControlContextMenuPresented)
        }
    }
    @ObservationIgnored private var isSiteControlContextMenuPresentedStorage = false
    private(set) var triggerFrameInGlobal: CGRect?
    private(set) var searchFocusRequest = 0
    @ObservationIgnored private var consumedSearchFocusRequest = 0
    @ObservationIgnored private let defaults: UserDefaults?
    @ObservationIgnored private let persistenceKey: String
    @ObservationIgnored private var lastSelectedSurface = BrowserUtilitySurface.archive

    init(
        defaults: UserDefaults? = nil,
        persistenceKey: String = selectedSurfaceDefaultsKey
    ) {
        self.defaults = defaults
        self.persistenceKey = persistenceKey
        if let rawValue = defaults?.string(forKey: persistenceKey),
            let persistedSurface = BrowserUtilitySurface.named(rawValue)
        {
            lastSelectedSurface = persistedSurface
        }
    }

    var isSiteControlInteractionActive: Bool {
        isSiteControlPresented || isSiteControlContextMenuPresented
    }

    var isSidebarInteractionActive: Bool {
        isSwitcherExpanded || isSiteControlInteractionActive
    }

    func recordTriggerFrame(_ frame: CGRect) {
        guard frame != triggerFrameInGlobal else { return }
        triggerFrameInGlobal = frame
    }

    func setSiteControlPresented(_ isPresented: Bool) {
        guard isPresented != isSiteControlPresented else { return }
        isSiteControlPresented = isPresented
    }

    func setSiteControlContextMenuPresented(_ isPresented: Bool) {
        guard isPresented != isSiteControlContextMenuPresented else { return }
        isSiteControlContextMenuPresented = isPresented
    }

    /// Replaces the utility and cancels focus requests belonging to the previous surface.
    func present(_ surface: BrowserUtilitySurface) {
        if self.surface != surface { consumedSearchFocusRequest = searchFocusRequest }
        self.surface = surface
        lastSelectedSurface = surface
        defaults?.set(surface.name, forKey: persistenceKey)
        isSwitcherExpanded = true
    }

    /// Records a request that stays pending until the owning search field can receive it.
    func focusSearch() {
        guard surface != nil else { return }
        searchFocusRequest &+= 1
    }

    /// A matching mounted toolbar may acknowledge the latest request once; stale fields cannot replay it.
    func consumeSearchFocusRequest(_ request: Int, for surface: BrowserUtilitySurface) -> Bool {
        guard self.surface == surface, request == searchFocusRequest, request != consumedSearchFocusRequest else {
            return false
        }
        consumedSearchFocusRequest = request
        return true
    }

    /// Stale utility dismissals cannot close a replacement or cancel its pending focus request.
    func dismiss(_ surface: BrowserUtilitySurface) {
        guard self.surface == surface else { return }
        self.surface = nil
        consumedSearchFocusRequest = searchFocusRequest
        isSwitcherExpanded = false
    }

    /// Closing a utility also discards focus that was requested before its field became available.
    func dismiss() {
        surface = nil
        consumedSearchFocusRequest = searchFocusRequest
        isSwitcherExpanded = false
    }

    func toggleSwitcher(hasNewDownloads: Bool = false) {
        if isSwitcherExpanded {
            dismiss()
        } else {
            present(hasNewDownloads ? .downloads : lastSelectedSurface)
        }
    }

    func handleInteraction(_ interactionSurface: BrowserUtilityInteractionSurface) {
        guard interactionSurface.dismissesUtilities else { return }
        dismiss()
    }
}

extension BrowserUtilityPresentationState: BrowserStoreFirstObservable {}
