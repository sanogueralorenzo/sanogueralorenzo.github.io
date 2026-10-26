import CrestCoreABI
import Foundation
import Observation
import Synchronization

// MARK: - Types

/// Holds the answer the core hands `crest_engine_ask`'s callback, borrowed for
/// the call.
final class EngineAnswer {
    var bytes: [UInt8]?
}

/// The app's one connection to the core's typed application API.
///
/// `send` runs an intent and applies the changes it caused to `state` before
/// returning them, so a caller reads the new state straight away. The core
/// answers any changes still pending first, so an older change never lands
/// after a newer one. A rule that
/// refuses an intent or a query throws its `Rejection`. Every other failure is
/// a build bug (a core and a Swift client built from different contracts) and
/// stops the app with a message naming the status.
///
/// `query` may be called from any thread: it reads only the immutable handle,
/// and a query never changes the core's state or `state`. Intents stay on the
/// main actor, except the cloud transport's, which `deliver` sends from the
/// transport's own thread.
///
/// Changes the core starts itself, such as a finished save or a cloud merge,
/// arrive through a payload-free wake that hops to the main queue and drains
/// them, at most once per main-queue turn.
@MainActor
@Observable
final class CrestCore {
    // MARK: - Types

    /// A registration to hear something the core did, which lasts as long as
    /// its owner.
    struct Follower<Value> {
        weak var owner: AnyObject?
        let handler: @MainActor (Value) -> Void
    }

    // MARK: - Variables

    /// The read model. Only the changes the core returns update it.
    let state = CoreState()
    /// The engines this core hosts pages on, which the composition registers.
    @ObservationIgnored private(set) lazy var engines = Engines(core: self)
    /// Where the core keeps `session.sqlite`; nil when it keeps everything in
    /// memory.
    let storageDirectory: URL?
    /// Called for each save the core started itself and could not finish.
    @ObservationIgnored var storageFailureHandler: ((StorageFailure) -> Void)?
    /// Called each time the core staged the session's edits in its sync
    /// journal, so the cloud transport can schedule an upload.
    @ObservationIgnored var syncJournalChangeHandler: (() -> Void)?
    @ObservationIgnored nonisolated let handle: UInt64
    @ObservationIgnored private let wake = CoreWakeRelay()
    /// Callers waiting for a revision to reach disk. A drain resumes them.
    @ObservationIgnored var saveWaiters: [(revision: Int64, continuation: CheckedContinuation<Void, Never>)] = []
    /// Who hears that an intent from the cloud transport committed.
    @ObservationIgnored private var cloudDeliveryFollowers: [Follower<Void>] = []
    /// Who hears each site permission change once it is applied. Until WP C
    /// (e) moves live revocation into engine commands, the pages' permission
    /// plumbing learns this way what a change covered.
    @ObservationIgnored private var sitePermissionFollowers: [Follower<SitePermissionsChanged>] = []
    @ObservationIgnored private var notificationAccessFollowers: [Follower<Void>] = []
    /// Who hears the questions the core asks the person and those that no
    /// longer wait, once their batch is applied.
    @ObservationIgnored private var promptFollowers: [Follower<any CorePromptChange>] = []
    /// Who hears each download record the core changed, once its batch is
    /// applied.
    @ObservationIgnored private var downloadFollowers: [Follower<DownloadState>] = []
    /// Who hears each download an engine began on a page, once its batch is
    /// applied.
    @ObservationIgnored private var downloadStartFollowers: [Follower<DownloadStarted>] = []
    /// Who hears each tab page the core unloaded under memory pressure, once
    /// its batch is applied.
    @ObservationIgnored private var unloadFollowers: [Follower<PageUnloaded>] = []
    /// Who hears each saved or pinned tab's page put away, once its batch is
    /// applied.
    @ObservationIgnored private var putAwayFollowers: [Follower<TabPagePutAway>] = []
    /// Who hears each page the core moved to another engine, once its batch
    /// is applied.
    @ObservationIgnored private var rehostFollowers: [Follower<PageRehosted>] = []
    /// Who hears each page an engine opened by itself that the core adopted
    /// for a tab, once its batch is applied.
    @ObservationIgnored private var adoptionFollowers: [Follower<OfferedPageAdopted>] = []
    /// Who hears each window the core brings to the front, once its batch is
    /// applied.
    @ObservationIgnored private var broughtForwardFollowers: [Follower<WindowBroughtForward>] = []
    @ObservationIgnored private var windowAdoptionFollowers: [Follower<OfferedWindowAdopted>] = []
    /// Who hears each Quick Window or Peek page the core closed, once its
    /// batch is applied.
    @ObservationIgnored private var transientCloseFollowers: [Follower<TransientPageClosed>] = []
    /// Who waits for each close preparation to end, by its request.
    @ObservationIgnored private var closeWaiters: [UUID: @MainActor (Bool) -> Void] = [:]
    /// Whether the app prepares to quit, or quits: a quit asked for that the
    /// core has not refused. No window closes on request meanwhile.
    @ObservationIgnored private(set) var isQuitting = false
    /// What waits for each data deletion to end, by its request.
    @ObservationIgnored private var dataDeletionWaiters: [UUID: @MainActor (Bool) -> Void] = [:]
    /// What waits for each website data reading to end, by its request.
    @ObservationIgnored private var websiteDataWaiters: [UUID: @MainActor (WebsiteDataRead?) -> Void] = [:]
    #if DEBUG
        /// Hears each batch of changes once `state` has applied it, so a test
        /// can apply the same batch again.
        @ObservationIgnored var batchApplied: (([Change]) -> Void)?
    #endif

    // MARK: - Initializers

    /// A memory-only core. Nothing it holds is saved.
    convenience init() {
        do {
            try self.init(configuration: AppConfiguration(storageDirectory: nil))
        } catch {
            preconditionFailure("A memory-only core refused to open: \(error). Rebuild the core.")
        }
    }

    /// A core configured once, at creation. With a storage directory the core
    /// opens the session file there; it throws the rejection naming why that
    /// file cannot be used.
    init(configuration: AppConfiguration) throws(Rejection) {
        var writer = WireWriter()
        configuration.encode(into: &writer)
        var handle: UInt64 = 0
        var refusal = crest_buffer_t()
        let status = CoreCodec.fingerprint.withUnsafeBufferPointer { fingerprint in
            writer.bytes.withUnsafeBufferPointer { settings in
                crest_app_create(
                    fingerprint.baseAddress, fingerprint.count, settings.baseAddress, settings.count, &handle, &refusal)
            }
        }
        defer { crest_buffer_free(&refusal) }
        switch status {
        case CREST_OK:
            self.handle = handle
        case CREST_REJECTED:
            throw Self.rejection(in: refusal)
        default:
            Self.buildBug(status, "create the core")
        }
        storageDirectory = configuration.storageDirectory.map { URL(fileURLWithPath: $0, isDirectory: true) }
        wake.core = self
        state.favicons.takePageImage = { [weak self] in self?.engines.takeIcon(of: $0) }
        let installed = crest_app_set_wake(handle, relayCoreWake, Unmanaged.passUnretained(wake).toOpaque())
        guard installed == CREST_OK else { Self.buildBug(installed, "set its wake callback") }
        state.enginePreferences = try query(GetEnginePreferences())
        state.agentPreferences = try query(GetAgentPreferences())
    }

    deinit {
        // No wake may reach the relay once the core is gone.
        crest_app_set_wake(handle, nil, nil)
        crest_app_destroy(handle)
    }

    // MARK: - Actions - Intents

    /// Runs one intent and returns the changes it caused, already applied to
    /// `state`. An intent that does not apply to the current state returns none.
    @discardableResult
    func send(_ intent: some Intent) throws(Rejection) -> [Change] {
        var writer = WireWriter()
        intent.encodeIntent(into: &writer)
        var reader = try call(crest_app_dispatch, writer, "send \(type(of: intent))")
        let changes = Self.decodeChanges(from: &reader, "\(type(of: intent))")
        apply(changes)
        return changes
    }

    // MARK: - Actions - Closing

    /// Asks the core to prepare the close `request` asks for, and calls
    /// `completion` once it ends: whether every page it covers may go and, for
    /// a quit, whether the person agreed to stop downloads in progress. A
    /// request the core refuses, such as one made while another preparation is
    /// under way, answers false at once, or hands `refused` the rule that
    /// refused it when there is one to hear it.
    func prepareToClose(
        _ request: some CloseRequest, refused: (@MainActor (Rejection) -> Void)? = nil,
        completion: @escaping @MainActor (Bool) -> Void
    ) {
        let quits = request.quits
        if quits { isQuitting = true }
        closeWaiters[request.requestID] = { [weak self] allowed in
            if quits, !allowed { self?.isQuitting = false }
            completion(allowed)
        }
        do {
            try send(request)
        } catch {
            let waiter = closeWaiters.removeValue(forKey: request.requestID)
            guard let refused else {
                waiter?(false)
                return
            }
            if quits { isQuitting = false }
            refused(error)
        }
    }

    /// Erases what every registered engine keeps for a profile, as `request`
    /// asks, and answers whether each of them erased all of it. A request the
    /// core refuses erases nothing.
    func deleteData(_ request: some DataDeletionRequest) async -> Bool {
        await withCheckedContinuation { continuation in
            dataDeletionWaiters[request.requestID] = { continuation.resume(returning: $0) }
            do {
                try send(request)
            } catch {
                dataDeletionWaiters.removeValue(forKey: request.requestID)?(false)
            }
        }
    }

    /// The sites that keep data in a profile on every registered engine, as
    /// `request` asks, or nil when the core refuses it.
    func readWebsiteData(_ request: ReadWebsiteData) async -> WebsiteDataRead? {
        await withCheckedContinuation { continuation in
            websiteDataWaiters[request.requestID] = { continuation.resume(returning: $0) }
            do {
                try send(request)
            } catch {
                websiteDataWaiters.removeValue(forKey: request.requestID)?(nil)
            }
        }
    }

    // MARK: - Actions - Cloud sync

    /// Runs one intent from the cloud transport on the calling thread, which
    /// the app keeps off the main thread: the core computes it there and takes
    /// its lock only to commit. It is on disk with its journal when this
    /// returns. What it changed reaches `state` through the wake and the drain
    /// after it, as one batch; then whoever follows cloud deliveries hears it.
    /// Answers the receipts the core answered, none of which change `state`.
    /// Throws the rule that refused it or the save that failed; either changed
    /// nothing.
    @discardableResult
    nonisolated func deliver(_ intent: some CloudSyncIntent) throws(Rejection) -> [Change] {
        var writer = WireWriter()
        intent.encodeIntent(into: &writer)
        var reader = try call(crest_app_dispatch, writer, "send \(type(of: intent))")
        let receipts = Self.decodeChanges(from: &reader, "\(type(of: intent))")
        // The wake queued the drain that brings what the intent changed before
        // the core answered, so this runs after it.
        DispatchQueue.main.async { [self] in
            MainActor.assumeIsolated { cloudIntentDelivered() }
        }
        return receipts
    }

    /// Runs one intent from the cloud transport about its own state on this
    /// device, on the calling thread, which the app keeps off the main thread.
    /// It is on disk when this returns. Answers the state it left, and the
    /// merge `BeginCloudMerge` began; neither changes `state`. Throws the rule
    /// that refused it or the save that failed; either changed nothing.
    @discardableResult
    nonisolated func transport(_ intent: some CloudTransportIntent) throws(Rejection) -> [Change] {
        var writer = WireWriter()
        intent.encodeIntent(into: &writer)
        var reader = try call(crest_app_dispatch, writer, "send \(type(of: intent))")
        return Self.decodeChanges(from: &reader, "\(type(of: intent))")
    }

    /// Returns once every sync stage the core queued before the call has
    /// committed, failed or been superseded, without waiting out a coalescing
    /// delay. The wait runs off the main thread, which stays free meanwhile.
    nonisolated func settleSync() async {
        await Task.detached(priority: .utility) { [handle] in
            let status = crest_app_settle_sync(handle)
            guard status == CREST_OK else { Self.buildBug(status, "settle its sync stages") }
        }.value
    }

    /// Calls `handler` each time an intent from the cloud transport commits,
    /// once the drain that brought what it changed has landed. The
    /// registration lasts as long as `owner`.
    func followCloudDeliveries(_ owner: AnyObject, _ handler: @escaping @MainActor () -> Void) {
        cloudDeliveryFollowers.removeAll { $0.owner == nil }
        cloudDeliveryFollowers.append(Follower(owner: owner, handler: handler))
    }

    private func cloudIntentDelivered() {
        cloudDeliveryFollowers.removeAll { $0.owner == nil }
        for follower in cloudDeliveryFollowers { follower.handler(()) }
    }

    // MARK: - Actions - Queries

    nonisolated func query<Question: Query>(_ query: Question) throws(Rejection) -> Question.Answer {
        var writer = WireWriter()
        query.encodeQuery(into: &writer)
        var reader = try call(crest_app_query, writer, "answer \(Question.self)")
        do {
            let answer = try Question.decodeAnswer(from: &reader)
            try reader.finish()
            return answer
        } catch {
            preconditionFailure("The core's answer to \(Question.self) does not decode (\(error)). Rebuild the core.")
        }
    }

    /// Answers, without a core, a query that reads no state: `SamePage`,
    /// `LanguagesMatching`, `TranslationChoice`, or `ResolveAddress` without a
    /// workspace. Any other query is a build bug, since only a core answers it.
    nonisolated static func answer<Question: Query>(_ query: Question) throws(Rejection) -> Question.Answer {
        var writer = WireWriter()
        query.encodeQuery(into: &writer)
        var buffer = crest_buffer_t()
        let status = CoreCodec.fingerprint.withUnsafeBufferPointer { fingerprint in
            writer.bytes.withUnsafeBufferPointer {
                crest_core_answer(fingerprint.baseAddress, fingerprint.count, $0.baseAddress, $0.count, &buffer)
            }
        }
        defer { crest_buffer_free(&buffer) }
        switch status {
        case CREST_OK: break
        case CREST_REJECTED: throw rejection(in: buffer)
        default: buildBug(status, "answer \(Question.self) without a core")
        }
        var reader = WireReader(buffer.bytes.map { Array(UnsafeBufferPointer(start: $0, count: buffer.length)) } ?? [])
        do {
            let answer = try Question.decodeAnswer(from: &reader)
            try reader.finish()
            return answer
        } catch {
            preconditionFailure("The core's answer to \(Question.self) does not decode (\(error)). Rebuild the core.")
        }
    }

    // MARK: - Actions - Changes

    /// Applies the changes the core started itself since the last drain, then
    /// answers the callers waiting for them. Answers the changes it applied.
    @discardableResult
    func drain() -> [Change] {
        var buffer = crest_buffer_t()
        let status = crest_app_drain(handle, &buffer)
        defer { crest_buffer_free(&buffer) }
        guard status == CREST_OK else { Self.buildBug(status, "drain its changes") }
        let length = buffer.length
        var reader = WireReader(buffer.bytes.map { Array(UnsafeBufferPointer(start: $0, count: length)) } ?? [])
        let changes = Self.decodeChanges(from: &reader, "its own work")
        apply(changes)
        resumeSaveWaiters()
        return changes
    }

    /// Applies one batch to `state`, in order, and reports a failed save the
    /// core started itself. Each change notes in the batch what it tells those
    /// who follow it, who hear it once the whole batch is applied.
    private func apply(_ changes: [Change]) {
        var batch = CoreChangeBatch()
        for change in changes { change.apply(to: self, in: &batch) }
        state.finishBatch()
        // Profile notifications have no live page to withdraw them when a
        // Space locks, disappears, or changes its permission choices.
        if batch.notificationAccessChanged {
            notificationAccessFollowers.removeAll { $0.owner == nil }
            for follower in notificationAccessFollowers { follower.handler(()) }
        }
        if !batch.pageRecords.isEmpty { engines.recordsApplied(batch.pageRecords) }
        if !batch.permissionChanges.isEmpty { sitePermissionsChanged(batch.permissionChanges) }
        if !batch.prompts.isEmpty { promptsChanged(batch.prompts) }
        if !batch.downloads.isEmpty { downloadsChanged(batch.downloads) }
        if !batch.startedDownloads.isEmpty { downloadsStarted(batch.startedDownloads) }
        if !batch.unloadedPages.isEmpty { pagesUnloaded(batch.unloadedPages) }
        if !batch.putAwayPages.isEmpty { pagesPutAway(batch.putAwayPages) }
        // The page's owner hosts it on its new engine before anyone hears it moved.
        if !batch.movedPages.isEmpty { engines.pagesMoved(batch.movedPages) }
        if !batch.rehostedPages.isEmpty { pagesRehosted(batch.rehostedPages) }
        if !batch.adoptedPages.isEmpty { pagesAdopted(batch.adoptedPages) }
        if !batch.broughtForward.isEmpty { windowsBroughtForward(batch.broughtForward) }
        if !batch.adoptedWindows.isEmpty { windowsAdopted(batch.adoptedWindows) }
        if !batch.closedTransientPages.isEmpty { transientPagesClosed(batch.closedTransientPages) }
        #if DEBUG
            batchApplied?(changes)
        #endif
        // Last, because a waiter may send the intent its close was waiting for.
        for ready in batch.closesReady { closeWaiters.removeValue(forKey: ready.requestID)?(ready.allowed) }
        for deleted in batch.dataDeleted {
            dataDeletionWaiters.removeValue(forKey: deleted.requestID)?(deleted.deleted)
        }
        for read in batch.websiteDataRead { websiteDataWaiters.removeValue(forKey: read.requestID)?(read) }
    }

    /// Calls `handler` with each site permission change once its batch is
    /// applied, so a decision asked from the handler reads the new choices.
    /// The registration lasts as long as `owner`.
    func followSitePermissions(_ owner: AnyObject, _ handler: @escaping @MainActor (SitePermissionsChanged) -> Void) {
        sitePermissionFollowers.removeAll { $0.owner == nil }
        sitePermissionFollowers.append(Follower(owner: owner, handler: handler))
    }

    func followNotificationAccess(_ owner: AnyObject, _ handler: @escaping @MainActor () -> Void) {
        notificationAccessFollowers.removeAll { $0.owner == nil }
        notificationAccessFollowers.append(Follower(owner: owner) { _ in handler() })
    }

    /// Shows `host` each question the core asks the person and closes each
    /// one that no longer waits, in order, once its batch is applied. The
    /// registration lasts as long as `host`.
    func followPrompts(_ host: some CorePromptHost) {
        promptFollowers.removeAll { $0.owner == nil }
        promptFollowers.append(
            Follower(owner: host) { [weak host] prompt in
                guard let host else { return }
                prompt.present(on: host)
            })
    }

    /// Calls `handler` with each download record the core changed, in order,
    /// once its batch is applied. The registration lasts as long as `owner`.
    func followDownloads(_ owner: AnyObject, _ handler: @escaping @MainActor (DownloadState) -> Void) {
        downloadFollowers.removeAll { $0.owner == nil }
        downloadFollowers.append(Follower(owner: owner, handler: handler))
    }

    /// Calls `handler` with each download an engine began on a page, once its
    /// batch is applied, so the window hosting that page shows it leaving. The
    /// download's record is already in `state`. The registration lasts as long
    /// as `owner`.
    func followStartedDownloads(_ owner: AnyObject, _ handler: @escaping @MainActor (DownloadStarted) -> Void) {
        downloadStartFollowers.removeAll { $0.owner == nil }
        downloadStartFollowers.append(Follower(owner: owner, handler: handler))
    }

    /// Calls `handler` with each tab page the core unloaded under memory
    /// pressure, once its batch is applied: the core already closed what the
    /// page's engine held, so its owner lets the page go without releasing it.
    /// The registration lasts as long as `owner`.
    func followUnloadedPages(_ owner: AnyObject, _ handler: @escaping @MainActor (PageUnloaded) -> Void) {
        unloadFollowers.removeAll { $0.owner == nil }
        unloadFollowers.append(Follower(owner: owner, handler: handler))
    }

    /// Calls `handler` with each saved or pinned tab's page the core put away,
    /// once its batch is applied, so the page host of the window that asked
    /// lets the page go. The registration lasts as long as `owner`.
    func followPutAwayPages(_ owner: AnyObject, _ handler: @escaping @MainActor (TabPagePutAway) -> Void) {
        putAwayFollowers.removeAll { $0.owner == nil }
        putAwayFollowers.append(Follower(owner: owner, handler: handler))
    }

    private func pagesPutAway(_ pages: [TabPagePutAway]) {
        putAwayFollowers.removeAll { $0.owner == nil }
        let followers = putAwayFollowers
        for page in pages {
            for follower in followers { follower.handler(page) }
        }
    }

    /// Calls `handler` with each page the core moved to another engine, once
    /// its batch is applied: the page on its new engine is already in
    /// `state`. The registration lasts as long as `owner`.
    func followRehostedPages(_ owner: AnyObject, _ handler: @escaping @MainActor (PageRehosted) -> Void) {
        rehostFollowers.removeAll { $0.owner == nil }
        rehostFollowers.append(Follower(owner: owner, handler: handler))
    }

    private func pagesRehosted(_ pages: [PageRehosted]) {
        rehostFollowers.removeAll { $0.owner == nil }
        let followers = rehostFollowers
        for page in pages {
            for follower in followers { follower.handler(page) }
        }
    }

    /// Calls `handler` with each page an engine opened by itself that the core
    /// adopted for a tab, once its batch is applied, so the window that hosts
    /// the page shows it. The registration lasts as long as `owner`.
    func followAdoptedPages(_ owner: AnyObject, _ handler: @escaping @MainActor (OfferedPageAdopted) -> Void) {
        adoptionFollowers.removeAll { $0.owner == nil }
        adoptionFollowers.append(Follower(owner: owner, handler: handler))
    }

    /// Calls `handler` with each window a page asked for that the core adopted
    /// as a Quick Window page, once its batch is applied, so the window that
    /// hosts the page shows it. The registration lasts as long as `owner`.
    func followAdoptedWindows(_ owner: AnyObject, _ handler: @escaping @MainActor (OfferedWindowAdopted) -> Void) {
        windowAdoptionFollowers.removeAll { $0.owner == nil }
        windowAdoptionFollowers.append(Follower(owner: owner, handler: handler))
    }

    private func windowsAdopted(_ windows: [OfferedWindowAdopted]) {
        windowAdoptionFollowers.removeAll { $0.owner == nil }
        let followers = windowAdoptionFollowers
        for window in windows {
            for follower in followers { follower.handler(window) }
        }
    }

    /// Calls `handler` with each Quick Window or Peek page the core closed,
    /// because it closed itself or its engine closed it, once its batch is
    /// applied, so whatever shows the page closes. The registration lasts as
    /// long as `owner`.
    func followClosedTransientPages(
        _ owner: AnyObject, _ handler: @escaping @MainActor (TransientPageClosed) -> Void
    ) {
        transientCloseFollowers.removeAll { $0.owner == nil }
        transientCloseFollowers.append(Follower(owner: owner, handler: handler))
    }

    private func transientPagesClosed(_ pages: [TransientPageClosed]) {
        transientCloseFollowers.removeAll { $0.owner == nil }
        let followers = transientCloseFollowers
        for page in pages {
            for follower in followers { follower.handler(page) }
        }
    }

    private func pagesAdopted(_ pages: [OfferedPageAdopted]) {
        adoptionFollowers.removeAll { $0.owner == nil }
        let followers = adoptionFollowers
        for page in pages {
            for follower in followers { follower.handler(page) }
        }
    }

    /// Calls `handler` with each window the core brings to the front, once its
    /// batch is applied: what the window shows is already in `state`. The
    /// registration lasts as long as `owner`.
    func followWindowsBroughtForward(
        _ owner: AnyObject, _ handler: @escaping @MainActor (WindowBroughtForward) -> Void
    ) {
        broughtForwardFollowers.removeAll { $0.owner == nil }
        broughtForwardFollowers.append(Follower(owner: owner, handler: handler))
    }

    private func windowsBroughtForward(_ windows: [WindowBroughtForward]) {
        broughtForwardFollowers.removeAll { $0.owner == nil }
        let followers = broughtForwardFollowers
        for window in windows {
            for follower in followers { follower.handler(window) }
        }
    }

    private func pagesUnloaded(_ pages: [PageUnloaded]) {
        unloadFollowers.removeAll { $0.owner == nil }
        let followers = unloadFollowers
        for page in pages {
            for follower in followers { follower.handler(page) }
        }
    }

    private func downloadsChanged(_ downloads: [DownloadState]) {
        downloadFollowers.removeAll { $0.owner == nil }
        let followers = downloadFollowers
        for download in downloads {
            for follower in followers { follower.handler(download) }
        }
    }

    private func downloadsStarted(_ downloads: [DownloadStarted]) {
        downloadStartFollowers.removeAll { $0.owner == nil }
        let followers = downloadStartFollowers
        for download in downloads {
            for follower in followers { follower.handler(download) }
        }
    }

    private func promptsChanged(_ prompts: [any CorePromptChange]) {
        promptFollowers.removeAll { $0.owner == nil }
        let followers = promptFollowers
        for prompt in prompts {
            for follower in followers { follower.handler(prompt) }
        }
    }

    private func sitePermissionsChanged(_ changes: [SitePermissionsChanged]) {
        sitePermissionFollowers.removeAll { $0.owner == nil }
        let followers = sitePermissionFollowers
        for change in changes {
            for follower in followers { follower.handler(change) }
        }
    }

    /// Tells the core the main queue finished the turn a wake's drain followed,
    /// so the work it queued behind that turn, such as a sync stage, may start.
    func endTurn() {
        let status = crest_app_end_turn(handle)
        guard status == CREST_OK else { Self.buildBug(status, "end the main queue's turn") }
    }

    nonisolated private static func decodeChanges(from reader: inout WireReader, _ source: @autoclosure () -> String)
        -> [Change]
    {
        do {
            let count = try reader.readCount()
            var decoded: [Change] = []
            decoded.reserveCapacity(count)
            for _ in 0..<count { decoded.append(try Change(from: &reader)) }
            try reader.finish()
            return decoded
        } catch {
            preconditionFailure("The core's changes for \(source()) do not decode (\(error)). Rebuild the core.")
        }
    }

    // MARK: - Actions - Boundary

    private typealias Entry = (UInt64, UnsafePointer<UInt8>?, Int, UnsafeMutablePointer<crest_buffer_t>?) ->
        crest_status_t

    /// Calls one entry point and returns a reader over its answer, or throws
    /// the rejection it answered instead.
    nonisolated private func call(
        _ entry: Entry, _ writer: WireWriter, _ action: @autoclosure () -> String
    ) throws(Rejection) -> WireReader {
        var buffer = crest_buffer_t()
        let status = writer.bytes.withUnsafeBufferPointer { entry(handle, $0.baseAddress, $0.count, &buffer) }
        defer { crest_buffer_free(&buffer) }
        switch status {
        case CREST_OK:
            return WireReader(buffer.bytes.map { Array(UnsafeBufferPointer(start: $0, count: buffer.length)) } ?? [])
        case CREST_REJECTED:
            throw Self.rejection(in: buffer)
        default:
            Self.buildBug(status, action())
        }
    }

    /// The one rejection a refused call left in `buffer`.
    nonisolated static func rejection(in buffer: crest_buffer_t) -> Rejection {
        let length = buffer.length
        var reader = WireReader(buffer.bytes.map { Array(UnsafeBufferPointer(start: $0, count: length)) } ?? [])
        do {
            let rejection = try Rejection(from: &reader)
            try reader.finish()
            return rejection
        } catch {
            preconditionFailure("The core's rejection does not decode (\(error)). Rebuild the core.")
        }
    }

    nonisolated static func buildBug(_ status: crest_status_t, _ action: String) -> Never {
        let name =
            switch status {
            case CREST_INVALID_MESSAGE: "INVALID_MESSAGE"
            case CREST_INVALID_HANDLE: "INVALID_HANDLE"
            case CREST_VERSION_MISMATCH: "VERSION_MISMATCH"
            case CREST_INTERNAL_ERROR: "INTERNAL_ERROR"
            case CREST_INVALID_ARGUMENT: "INVALID_ARGUMENT"
            case CREST_LIMIT_EXCEEDED: "LIMIT_EXCEEDED"
            default: "status \(status)"
            }
        preconditionFailure(
            "The core could not \(action): \(name). The app and its core were built from different contracts; rebuild both."
        )
    }
}

/// Carries the core's wake from whichever thread published a change to one
/// drain on the main queue, which also ends the main queue's turn for the
/// core. A wake that finds a drain already queued adds nothing.
private final class CoreWakeRelay: Sendable {
    nonisolated(unsafe) weak var core: CrestCore?
    private let isScheduled = Atomic<Bool>(false)

    func schedule() {
        guard !isScheduled.exchange(true, ordering: .acquiringAndReleasing) else { return }
        DispatchQueue.main.async { [self] in
            isScheduled.store(false, ordering: .releasing)
            MainActor.assumeIsolated {
                core?.drain()
                core?.endTurn()
            }
        }
    }
}

/// The core's wake callback. It runs on the core thread that published a
/// change, outside every core lock, so it only schedules the drain.
private func relayCoreWake(_ context: UnsafeMutableRawPointer?) {
    guard let context else { return }
    Unmanaged<CoreWakeRelay>.fromOpaque(context).takeUnretainedValue().schedule()
}
