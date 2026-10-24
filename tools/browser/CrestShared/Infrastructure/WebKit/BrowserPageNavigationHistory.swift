import Foundation
import WebKit

/// WebKit leaves some entries out of its UI-facing lists and its
/// `canGoBack`/`canGoForward` while keeping them in the session: Navigation API
/// entries even after an allowed link click, and any entry a script created
/// without user activation once the page moves off it. Keep the actual WebKit
/// items we observed, so traversal preserves document state and does not
/// reload their URLs.
///
/// - Back still uses WebKit's filter for script-created entries without a link
///   activation, which keeps a page from trapping the person behind entries it
///   added on its own.
/// - Forward offers every entry ahead of the current one that the page has
///   shown, so the page the person just left by going back stays reachable.
@MainActor
struct BrowserPageNavigationHistory {
    // MARK: - Static Variables

    /// WebKit's own back-forward list capacity (`WebBackForwardList`'s
    /// `DefaultCapacity`). WebKit drops its oldest entry past it when a page
    /// commits, and its swipe gestures walk that list directly, so the
    /// supplement never keeps more than WebKit does.
    static let capacity = 100

    // MARK: - Variables

    private var entries: [WKBackForwardListItem] = []
    private var linkItems: Set<ObjectIdentifier> = []
    /// Entries that became current since the last document commit. A commit
    /// onto one of them is a new document rather than a return to history.
    private var arrivals: Set<ObjectIdentifier> = []
    private var currentIndex = 0
    private var pendingLinkURL: URL?
    private var pendingLinkSource: ObjectIdentifier?
    private(set) var backItems: [WKBackForwardListItem] = []
    private(set) var forwardItems: [WKBackForwardListItem] = []
    /// The identity each entry kept takes in the core, made when the entry
    /// is first seen. WebKit cannot carry it in the item itself, so it lasts
    /// as long as the entry does here.
    private var entryIDs: [ObjectIdentifier: UUID] = [:]
    /// The identity the next new entry takes: the core's, for an entry it
    /// asked the page to load again.
    private var nextEntryID: UUID?

    /// The page's history as the core keeps it: the entries Back and Forward
    /// reach and the current one, oldest first, and the index of the current
    /// one; nil before anything committed.
    var reported: (entries: [PageHistoryEntry], current: Int)? {
        guard entries.indices.contains(currentIndex) else { return nil }
        let listed = backItems + [entries[currentIndex]] + forwardItems
        return (listed.compactMap(entry), backItems.count)
    }

    // MARK: - Actions - Navigation

    /// The item for the entry `entryID` names, when the page still keeps it.
    func item(_ entryID: UUID) -> WKBackForwardListItem? {
        entries.first { entryIDs[ObjectIdentifier($0)] == entryID }
    }

    /// The next entry the page commits takes `entryID`.
    mutating func expectEntry(_ entryID: UUID?) {
        nextEntryID = entryID
    }

    /// A new entry takes the identity the core's load expected, if any.
    private mutating func takeExpectedEntry(_ item: WKBackForwardListItem) {
        guard let expected = nextEntryID else { return }
        entryIDs[ObjectIdentifier(item)] = expected
        nextEntryID = nil
    }

    private func entry(_ item: WKBackForwardListItem) -> PageHistoryEntry? {
        guard let id = entryIDs[ObjectIdentifier(item)] else { return nil }
        return PageHistoryEntry(id: id, url: item.url.absoluteString, title: item.title ?? "")
    }

    mutating func recordLink(to url: URL?, in list: WKBackForwardList) {
        synchronize(with: list)
        if let current = list.currentItem {
            linkItems.insert(ObjectIdentifier(current))
        }
        pendingLinkSource = list.currentItem.map(ObjectIdentifier.init)
        pendingLinkURL = url
    }

    /// A document committed. A new entry replaces the document the supplements
    /// described, and WebKit may drop the entries it omits from its lists with
    /// it, so history returns to WebKit's own list. Returning to an entry the
    /// page already showed, by going back or forward or reloading, keeps them,
    /// including the entries ahead that the person just left.
    mutating func documentDidCommit(in list: WKBackForwardList) {
        synchronize(with: list)
        defer { arrivals = [] }
        guard let current = list.currentItem, arrivals.contains(ObjectIdentifier(current)) else { return }
        // Entries WebKit keeps keep the identities the core knows them by.
        let kept = entryIDs
        self = BrowserPageNavigationHistory()
        entryIDs = kept
        synchronize(with: list)
    }

    mutating func synchronize(with list: WKBackForwardList) {
        guard let current = list.currentItem else { return }
        let nativeBack = list.backList
        let nativeForward = list.forwardList
        if entries.isEmpty {
            entries = nativeBack + [current] + nativeForward
            arrivals.insert(ObjectIdentifier(current))
            // A new page's only entry is the load the core asked for, never a
            // list WebKit restored.
            if nativeBack.isEmpty, nativeForward.isEmpty { takeExpectedEntry(current) }
        } else if !entries.contains(where: { $0 === current }) {
            // A new entry discards the old forward branch. A restored list may
            // contain entries we have not observed yet; seed those below too.
            entries = Array(entries.prefix(currentIndex + 1)) + [current]
            arrivals.insert(ObjectIdentifier(current))
            takeExpectedEntry(current)
        }
        // Merge native entries in their own order. This also seeds history
        // restored by WebKit without manufacturing entries from URL strings.
        var anchor = current
        for item in nativeBack.reversed() {
            if !entries.contains(where: { $0 === item }),
                let index = entries.firstIndex(where: { $0 === anchor })
            {
                entries.insert(item, at: index)
            }
            anchor = item
        }
        anchor = current
        for item in nativeForward {
            if !entries.contains(where: { $0 === item }),
                let index = entries.firstIndex(where: { $0 === anchor })
            {
                entries.insert(item, at: index + 1)
            }
            anchor = item
        }
        currentIndex = entries.firstIndex(where: { $0 === current }) ?? 0
        if let pendingLinkURL, pendingLinkSource != ObjectIdentifier(current) {
            if current.url == pendingLinkURL {
                linkItems.insert(ObjectIdentifier(current))
            }
            self.pendingLinkURL = nil
            pendingLinkSource = nil
        }
        // Match WebKit's bounded session list instead of retaining old items
        // after its oldest entries have been evicted.
        if entries.count > Self.capacity {
            let removed = min(entries.count - Self.capacity, currentIndex)
            entries.removeFirst(removed)
            currentIndex -= removed
            entries = Array(entries.prefix(Self.capacity))
        }
        let retained = Set(entries.map(ObjectIdentifier.init))
        linkItems.formIntersection(retained)
        arrivals.formIntersection(retained)
        entryIDs = entryIDs.filter { retained.contains($0.key) }
        for item in entries where entryIDs[ObjectIdentifier(item)] == nil {
            entryIDs[ObjectIdentifier(item)] = UUID()
        }
        let allowed = linkItems.union((nativeBack + nativeForward).map(ObjectIdentifier.init))
        backItems = entries.prefix(currentIndex).filter { allowed.contains(ObjectIdentifier($0)) }
        forwardItems = Array(entries.dropFirst(currentIndex + 1))
    }
}
