import Foundation
import Observation
import SwiftUI

@Observable
@MainActor
final class BrowserUtilityPresentationState {
    static let triggerSurfacesDefaultsKey = "browser.utility.trigger-surfaces"
    /// Where earlier releases kept the one list the button last opened, which
    /// still answers for a Space nobody has chosen a list for.
    static let lastSurfaceDefaultsKey = "browser.utility.selected-surface"

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
    /// The list the sidebar's lists button opens and wears the symbol of in
    /// each Space, by the Space's ID, as the person chose it from the button's
    /// menu there. Kept across launches on this device.
    private(set) var triggerSurfaces: [UUID: BrowserUtilitySurface] = [:]
    /// What a Space nobody has chosen a list for opens: the list an earlier
    /// release last opened, or the archive.
    @ObservationIgnored private let unchosenSurface: BrowserUtilitySurface

    init(
        defaults: UserDefaults? = nil,
        persistenceKey: String = triggerSurfacesDefaultsKey
    ) {
        self.defaults = defaults
        self.persistenceKey = persistenceKey
        unchosenSurface =
            defaults?.string(forKey: Self.lastSurfaceDefaultsKey).flatMap(BrowserUtilitySurface.named) ?? .archive
        triggerSurfaces = storedTriggerSurfaces
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
        isSwitcherExpanded = true
    }

    /// The list the lists button opens in the Space `spaceID` names.
    func triggerSurface(for spaceID: UUID?) -> BrowserUtilitySurface {
        spaceID.flatMap { currentTriggerSurfaces[$0] } ?? unchosenSurface
    }

    /// Makes `surface` the list the lists button opens in the Space `spaceID`
    /// names, and remembers it.
    ///
    /// Another window's presentation state over the same defaults may have
    /// saved since this one read them, so each save starts from the choices in
    /// effect now rather than from this state's own copy.
    func chooseTriggerSurface(_ surface: BrowserUtilitySurface, for spaceID: UUID) {
        var merged = currentTriggerSurfaces
        guard merged[spaceID] != surface else { return }
        merged[spaceID] = surface
        triggerSurfaces = merged
        var stored: [String: String] = [:]
        for (spaceID, surface) in merged { stored[spaceID.uuidString] = surface.name }
        defaults?.set(stored, forKey: persistenceKey)
    }

    /// The choices in effect now: this state's own copy, which views observe,
    /// with what the defaults hold winning, so a choice another window saved
    /// for the same Space counts.
    private var currentTriggerSurfaces: [UUID: BrowserUtilitySurface] {
        triggerSurfaces.merging(storedTriggerSurfaces) { _, stored in stored }
    }

    /// The choices the defaults hold now, by Space ID.
    private var storedTriggerSurfaces: [UUID: BrowserUtilitySurface] {
        guard let stored = defaults?.dictionary(forKey: persistenceKey) as? [String: String] else { return [:] }
        var surfaces: [UUID: BrowserUtilitySurface] = [:]
        for (spaceID, name) in stored {
            guard let spaceID = UUID(uuidString: spaceID), let surface = BrowserUtilitySurface.named(name) else {
                continue
            }
            surfaces[spaceID] = surface
        }
        return surfaces
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

    /// Opens the lists for the Space `spaceID` names, or closes them: unseen
    /// finished downloads open Downloads, otherwise the list chosen for that
    /// Space.
    func toggleSwitcher(for spaceID: UUID?, hasNewDownloads: Bool = false) {
        if isSwitcherExpanded {
            dismiss()
        } else {
            present(hasNewDownloads ? .downloads : triggerSurface(for: spaceID))
        }
    }

    func handleInteraction(_ interactionSurface: BrowserUtilityInteractionSurface) {
        guard interactionSurface.dismissesUtilities else { return }
        dismiss()
    }
}

extension BrowserUtilityPresentationState: BrowserStoreFirstObservable {}
