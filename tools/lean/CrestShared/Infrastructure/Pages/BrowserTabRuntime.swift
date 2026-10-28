import Foundation
import Observation

/// One tab's resident page, and on the Mac which window presents it. Each of
/// them is observed on its own, so a window presenting another tab redraws
/// only what reads this tab's page, and no reader of any other tab's. Each
/// value is stored before it is announced; see `BrowserStoreFirstObservable`.
@MainActor
@Observable
final class BrowserTabRuntime: BrowserStoreFirstObservable {
    var page: BrowserPlatformPage {
        get {
            access(keyPath: \.page)
            return pageStorage
        }
        set {
            guard pageStorage !== newValue else { return }
            pageStorage = newValue
            withMutation(keyPath: \.page) {}
        }
    }
    @ObservationIgnored private var pageStorage: BrowserPlatformPage
    #if os(macOS)
        @ObservationIgnored weak var store: BrowserPageRuntimeStore?
        var presentationWindowID: UUID? {
            get { observed(\.presentationWindowIDStorage, as: \.presentationWindowID) }
            set { publish(newValue, into: \.presentationWindowIDStorage, as: \.presentationWindowID) }
        }
        @ObservationIgnored private var presentationWindowIDStorage: UUID?
        @ObservationIgnored var routingWindowID: UUID?
        @ObservationIgnored var snapshotGeneration = 0
        var snapshot: BrowserPageSnapshotImage? {
            get {
                access(keyPath: \.snapshot)
                return snapshotStorage
            }
            set {
                guard snapshotStorage !== newValue else { return }
                snapshotStorage = newValue
                withMutation(keyPath: \.snapshot) {}
            }
        }
        @ObservationIgnored private var snapshotStorage: BrowserPageSnapshotImage?
    #endif

    var allPages: [BrowserPlatformPage] { [page] }

    init(page: BrowserPlatformPage) {
        pageStorage = page
    }

    /// Ends every page the tab holds; see `release(keepingState:)` on the page.
    func release(keepingState: Bool) {
        for page in allPages {
            page.release(keepingState: keepingState)
        }
    }

    /// Ends the tab's page the core unloaded; see `unloaded()` on the page.
    func unloaded() {
        page.unloaded()
    }
}
