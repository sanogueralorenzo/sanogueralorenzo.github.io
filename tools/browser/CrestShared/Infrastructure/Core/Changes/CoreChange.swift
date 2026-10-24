import Foundation

// MARK: - Types

/// What one batch of changes tells those who follow it, which `CrestCore`
/// hands them once `state` has applied the whole batch. Each change notes
/// itself here as it applies.
struct CoreChangeBatch {
    /// The navigations and icons the core recorded from pages' reports.
    var pageRecords = Engines.PageRecords()
    var permissionChanges: [SitePermissionsChanged] = []
    /// The questions the core asks the person, and each one that settles.
    var prompts: [any CorePromptChange] = []
    var downloads: [DownloadState] = []
    var startedDownloads: [DownloadStarted] = []
    var unloadedPages: [PageUnloaded] = []
    var putAwayPages: [TabPagePutAway] = []
    /// The pages whose engine the batch changed.
    var movedPages: [UUID] = []
    var rehostedPages: [PageRehosted] = []
    var adoptedPages: [OfferedPageAdopted] = []
    var broughtForward: [WindowBroughtForward] = []
    var adoptedWindows: [OfferedWindowAdopted] = []
    var closedTransientPages: [TransientPageClosed] = []
    var closesReady: [CloseReady] = []
    var dataDeleted: [DataDeleted] = []
    /// Whether the batch changed which Spaces may show notifications: a Space
    /// locked, went away, or changed its permission choices.
    var notificationAccessChanged = false
}

/// A change the core published. It applies itself to the read model, and it
/// notes in its batch what it tells those who follow the batch, so
/// `CrestCore` hands each follower what it hears without picking changes
/// apart. The generator makes every change adopt it; each change's own file
/// implements it.
protocol CoreChange {
    /// Applies the change to the read model.
    @MainActor func apply(to state: CoreState)

    /// Applies the change to `core`'s read model, as `apply(to:)` does, and
    /// notes in `batch` what it tells those who follow the batch, or tells
    /// `core` itself what it must hear at once. Most changes tell no one, so
    /// by default this only applies the change.
    @MainActor func apply(to core: CrestCore, in batch: inout CoreChangeBatch)

    /// Notes in `receipts` what the change tells the cloud transport whose
    /// intent it answers. Most changes tell it nothing, so by default this
    /// notes nothing.
    func note(in receipts: inout CloudTransportReceipts)
}

extension CoreChange {
    @MainActor func apply(to core: CrestCore, in batch: inout CoreChangeBatch) {
        apply(to: core.state)
    }

    func note(in receipts: inout CloudTransportReceipts) {}
}
