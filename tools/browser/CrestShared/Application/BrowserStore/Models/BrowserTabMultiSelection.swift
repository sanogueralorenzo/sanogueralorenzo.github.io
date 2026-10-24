import Foundation
import Observation

/// Window-local selection, separate from the tab whose page is active. The
/// core never sees it; it is this window's sidebar state. Each item's
/// membership is observed on its own, so selecting a row redraws that row and
/// no list, and a row asks whether the selection is engaged only while it is
/// selected. Every value is stored before it is announced; see
/// `BrowserStoreFirstObservable`.
@Observable
@MainActor
final class BrowserTabMultiSelection {
    // MARK: - Variables

    /// Which items are selected, each observed on its own.
    @ObservationIgnored private let members = ObservedSet<BrowserSelectionItemID>()
    /// Advances with every change of which items are selected, for the few
    /// readers that read the whole set.
    private var revision: Int {
        get { observed(\.revisionStorage, as: \.revision) }
        set { publish(newValue, into: \.revisionStorage, as: \.revision) }
    }
    @ObservationIgnored private var revisionStorage = 0

    /// The selected items. Reading them observes every change of the selection;
    /// a row reads `contains(_:)` instead.
    var selectedItems: Set<BrowserSelectionItemID> {
        _ = revision
        return members.members
    }
    var selectedIDs: Set<UUID> { Set(selectedItems.compactMap(\.tabID)) }
    private(set) var anchorItem: BrowserSelectionItemID? {
        get { observed(\.anchorItemStorage, as: \.anchorItem) }
        set { publish(newValue, into: \.anchorItemStorage, as: \.anchorItem) }
    }
    @ObservationIgnored private var anchorItemStorage: BrowserSelectionItemID?
    var anchorID: UUID? { anchorItem?.tabID }
    private(set) var focusedItem: BrowserSelectionItemID? {
        get { observed(\.focusedItemStorage, as: \.focusedItem) }
        set { publish(newValue, into: \.focusedItemStorage, as: \.focusedItem) }
    }
    @ObservationIgnored private var focusedItemStorage: BrowserSelectionItemID?
    var focusedID: UUID? { focusedItem?.tabID }
    private(set) var isEngaged: Bool {
        get { observed(\.isEngagedStorage, as: \.isEngaged) }
        set { publish(newValue, into: \.isEngagedStorage, as: \.isEngaged) }
    }
    @ObservationIgnored private var isEngagedStorage = false
    var ownsKeyboardFocus: Bool {
        get { observed(\.ownsKeyboardFocusStorage, as: \.ownsKeyboardFocus) }
        set { publish(newValue, into: \.ownsKeyboardFocusStorage, as: \.ownsKeyboardFocus) }
    }
    @ObservationIgnored private var ownsKeyboardFocusStorage = false
    /// What the person is told of an action on the selection the core refused.
    var message: String? {
        get { observed(\.messageStorage, as: \.message) }
        set { publish(newValue, into: \.messageStorage, as: \.message) }
    }
    @ObservationIgnored private var messageStorage: String?
    private(set) var rejectedPinnedIDs: Set<UUID> {
        get { observed(\.rejectedPinnedIDsStorage, as: \.rejectedPinnedIDs) }
        set { publish(newValue, into: \.rejectedPinnedIDsStorage, as: \.rejectedPinnedIDs) }
    }
    @ObservationIgnored private var rejectedPinnedIDsStorage: Set<UUID> = []
    private(set) var pinnedRejectionGeneration: Int {
        get { observed(\.pinnedRejectionGenerationStorage, as: \.pinnedRejectionGeneration) }
        set { publish(newValue, into: \.pinnedRejectionGenerationStorage, as: \.pinnedRejectionGeneration) }
    }
    @ObservationIgnored private var pinnedRejectionGenerationStorage = 0
    @ObservationIgnored private var rangeBase: Set<BrowserSelectionItemID>?

    // MARK: - Actions - Reading

    /// Whether the selection holds the item while it is engaged. Reading it
    /// observes only the item's own membership, and whether the selection is
    /// engaged only while the item is a member.
    func contains(_ id: BrowserSelectionItemID) -> Bool { members.contains(id) && isEngaged }

    func contains(_ id: UUID) -> Bool { contains(.tab(id)) }

    // MARK: - Actions - Selecting

    /// A shift click ranges from the anchor, or from `activeItem` when no
    /// anchor is set, such as right after a tab was opened or activated.
    func click(
        _ id: BrowserSelectionItemID, units: [[BrowserSelectionItemID]], command: Bool = false, shift: Bool = false,
        activeItem: BrowserSelectionItemID? = nil
    ) {
        guard let target = units.firstIndex(where: { $0.contains(id) }) else { return }
        focusedItem = units[target].first
        ownsKeyboardFocus = true
        if shift, anchorItem == nil, let activeItem, let active = units.first(where: { $0.contains(activeItem) }) {
            // A new anchor starts a new range, never one over a base an earlier anchor left.
            anchorItem = active.first
            rangeBase = nil
        }
        if shift, let anchorItem, let anchor = units.firstIndex(where: { $0.contains(anchorItem) }) {
            if rangeBase == nil { rangeBase = command ? members.members : [] }
            let range = Set(units[min(anchor, target)...max(anchor, target)].flatMap { $0 })
            select((rangeBase ?? []).union(range))
            isEngaged = true
            return
        }
        rangeBase = nil
        anchorItem = units[target].first
        let unit = Set(units[target])
        if command {
            select(unit.isSubset(of: members.members) ? members.members.subtracting(unit) : members.members.union(unit))
        } else {
            select(unit)
        }
        isEngaged = command || shift
    }

    func selectAll(units: [[BrowserSelectionItemID]]) {
        select(Set(units.flatMap { $0 }))
        anchorItem = units.first?.first
        focusedItem = units.last?.first
        rangeBase = nil
        isEngaged = true
        ownsKeyboardFocus = true
    }

    func selectForKeyboard(_ id: BrowserSelectionItemID, units: [[BrowserSelectionItemID]]) {
        click(id, units: units)
        isEngaged = true
    }

    /// Keeps only the items the sidebar still shows, and never part of a unit
    /// that changed under the selection.
    func reconcile(units: [[BrowserSelectionItemID]]) {
        let available = Set(units.flatMap { $0 })
        var next = members.members.intersection(available)
        rangeBase = rangeBase.map { $0.intersection(available) }
        if let anchorItem, !available.contains(anchorItem) { self.anchorItem = nil }
        if let focusedItem, !available.contains(focusedItem) { self.focusedItem = nil }
        // A changed group is never partially selected after a live update.
        for unit in units where !next.isDisjoint(with: unit) {
            if !Set(unit).isSubset(of: next) { next.subtract(unit) }
        }
        select(next)
    }

    func clear() {
        select([])
        anchorItem = nil
        focusedItem = nil
        rangeBase = nil
        isEngaged = false
        ownsKeyboardFocus = false
    }

    /// Lets go of the pinned tabs a drag would carry with other tabs or
    /// folders, which move apart, and shakes them; answers the items the drag
    /// still carries, or the capture unchanged when it holds no such pins.
    func releasePinnedTabs(from captured: BrowserCapturedSelection) -> [BrowserSelectionItemID]? {
        let pins = Set(captured.members.filter { $0.placement == .pinned }.map(\.id))
        guard !pins.isEmpty, pins.count < captured.ids.count || captured.hasFolders else { return nil }
        rejectedPinnedIDs = pins
        pinnedRejectionGeneration &+= 1
        select(members.members.subtracting(pins.map(BrowserSelectionItemID.tab)))
        rangeBase = nil
        let remaining = captured.ids.filter { !pins.contains($0) }
        if let anchorID, pins.contains(anchorID) { anchorItem = remaining.first.map(BrowserSelectionItemID.tab) }
        if let focusedID, pins.contains(focusedID) { focusedItem = remaining.first.map(BrowserSelectionItemID.tab) }
        return captured.rootItems.filter { $0.tabID.map(pins.contains) != true }
    }

    func click(_ id: UUID, units: [[BrowserSelectionItemID]], command: Bool = false, shift: Bool = false) {
        click(.tab(id), units: units, command: command, shift: shift)
    }

    func click(_ id: UUID, units: [[UUID]], command: Bool = false, shift: Bool = false) {
        click(.tab(id), units: units.map { $0.map(BrowserSelectionItemID.tab) }, command: command, shift: shift)
    }

    func selectAll(units: [[UUID]]) { selectAll(units: units.map { $0.map(BrowserSelectionItemID.tab) }) }
    func reconcile(units: [[UUID]]) { reconcile(units: units.map { $0.map(BrowserSelectionItemID.tab) }) }
    func selectForKeyboard(_ id: UUID, units: [[UUID]]) {
        selectForKeyboard(.tab(id), units: units.map { $0.map(BrowserSelectionItemID.tab) })
    }

    /// Takes a whole new set of selected items, announcing only the items that
    /// joined or left, and the change to the whole set's readers.
    private func select(_ items: Set<BrowserSelectionItemID>) {
        guard items != members.members else { return }
        members.replace(with: items)
        revision &+= 1
    }
}

extension BrowserTabMultiSelection: BrowserStoreFirstObservable {}
