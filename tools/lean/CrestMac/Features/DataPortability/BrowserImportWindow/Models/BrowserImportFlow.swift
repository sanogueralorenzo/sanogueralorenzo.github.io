import AppKit
import Foundation
import Observation

@Observable
@MainActor
final class BrowserImportFlow {
    // MARK: - Variables

    let browser: BrowserStore

    private(set) var installedSources: [BrowserInstalledImportSource] = []
    /// The browsers setup found by looking, once the person asked it to scan.
    private(set) var unlistedSources: [BrowserInstalledImportSource] = []
    /// Whether the person asked setup to scan the browsers' data. Until then
    /// setup reads only the browser the person chooses, when they go on.
    private(set) var hasScanned = false
    /// The found browser `ImportSource.otherChromium` imports, by its app.
    private(set) var chosenUnlistedSourceURL: URL?
    private(set) var isChoosingDataAccess = false
    /// The icons the extensions the browsers read offer wear, by identifier.
    private(set) var extensionIcons: [String: NSImage] = [:]

    @ObservationIgnored private let sourceDiscovery: any BrowserInstalledImportSourceDiscovering
    @ObservationIgnored private let dataAccessProvider: any BrowserImportDataAccessProviding
    @ObservationIgnored private let importReadCoordinator: BrowserImportReadCoordinator
    /// What installs the extensions an import brings, when the engine runs any.
    @ObservationIgnored private let extensionInstaller: (any BrowserImportedExtensionInstalling)?
    @ObservationIgnored private var currentImportPayload: BrowserDetectedImportPayload?
    /// The review's Spaces as the views draw them, for the review the core
    /// last published, so a view's body builds them once per change.
    @ObservationIgnored private var reviewCache: (review: ImportReview, spaces: [BrowserImportSpaceReview])?
    /// The session the review would leave, until the review changes.
    @ObservationIgnored private var previewCache: (review: ImportReview, session: BrowserSessionPreview?)?
    @ObservationIgnored private var operationGeneration = 0

    /// Setup as the core holds it, or nil before it opens.
    var state: ImportFlowState? { browser.core.state.importFlow }

    var step: ImportStep { state?.step ?? .importBrowser }
    var failure: ImportFailure? { state?.failure }
    var review: ImportReview? { state?.review }
    var selectedImportApplications: Set<ImportSource> { Set(state?.selected ?? []) }

    var isReading: Bool { importReadCoordinator.isInFlight }
    var isCommittingImport: Bool { state?.phase == .committing }

    var isImportSelectionLocked: Bool {
        isReading || isChoosingDataAccess || isCommittingImport
    }

    /// The review's Spaces as the review views draw them.
    var reviewSpaces: [BrowserImportSpaceReview] {
        guard let review else { return [] }
        if let reviewCache, reviewCache.review == review { return reviewCache.spaces }
        let spaces = review.spaces.map(BrowserImportSpaceReview.init)
        reviewCache = (review, spaces)
        return spaces
    }

    /// The Space the person is looking at in the review.
    var shownReviewSpaceID: UUID? {
        get { review?.shownSpaceID }
        set {
            guard let newValue, newValue != review?.shownSpaceID else { return }
            send(ShowImportSpace(sourceSpaceID: newValue))
        }
    }

    var completionSummary: LocalizedStringResource? {
        state?.summary.map(BrowserImportSummary.completed)
    }

    /// What the review's last Space offers: importing and going on to the
    /// next chosen browser, or importing alone.
    var importReviewActionTitle: LocalizedStringResource {
        state?.queue?.hasMoreAfterCurrent == true
            ? LocalizedStringResource(
                "Import & Continue",
                comment: "Button that imports the current browser and continues to the next selected browser.")
            : LocalizedStringResource(
                "Import", comment: "Button that imports the reviewed data from the final browser.")
    }

    // MARK: - Initializers

    /// A flow over `browser`'s workspace. It sends the core
    /// nothing until `start`, since a view may build it more than once.
    init(
        browser: BrowserStore,
        sourceDiscovery: any BrowserInstalledImportSourceDiscovering = LiveBrowserInstalledImportSourceDiscovery(),
        dataAccessProvider: any BrowserImportDataAccessProviding = LiveBrowserImportDataAccessProvider(),
        importReader: (any BrowserImportReading)? = nil,
        extensionInstaller: (any BrowserImportedExtensionInstalling)? = nil
    ) {
        self.browser = browser
        self.sourceDiscovery = sourceDiscovery
        self.dataAccessProvider = dataAccessProvider
        self.extensionInstaller = extensionInstaller
        importReadCoordinator = BrowserImportReadCoordinator(
            reader: importReader ?? LiveBrowserImportReader(core: browser.core))
    }

    // MARK: - Actions - Lifecycle

    /// Opens setup in the core for the request, offering the browsers found.
    func start() {
        send(StartBrowserImport(workspaceID: browser.family.workspaceID))
        offerInstalledSources()
    }

    /// Finds the browsers installed on this Mac by their apps, reading none
    /// of their data, and offers them to setup.
    func discoverInstalledSources() {
        installedSources = sourceDiscovery.installedSources()
        offerInstalledSources()
    }

    private func offerInstalledSources() {
        guard state != nil else { return }
        let unlisted: [ImportSource] = unlistedSources.isEmpty ? [] : [.otherChromium]
        send(OfferImportSources(installed: installedSources.map(\.application) + unlisted))
    }

    /// Reads what each listed browser keeps, and looks for the browsers built
    /// on Chromium that setup does not list, offering them beside the listed
    /// ones. macOS may say Crest looked at other apps' data, so setup scans
    /// only when the person asks.
    func scanForMore() {
        guard !isImportSelectionLocked else { return }
        installedSources = installedSources.map(sourceDiscovery.scanned)
        unlistedSources = sourceDiscovery.unlistedSources()
        hasScanned = true
        offerInstalledSources()
    }

    /// Every browser setup offers: the listed ones, then those it found.
    var offeredSources: [BrowserInstalledImportSource] { installedSources + unlistedSources }

    func isSelected(_ source: BrowserInstalledImportSource) -> Bool {
        guard selectedImportApplications.contains(source.application) else { return false }
        return source.application != .otherChromium || source.applicationURL == chosenUnlistedSourceURL
    }

    /// Chooses `source` or leaves it out. One found browser imports at a time,
    /// so choosing another found browser takes its place.
    func toggleSelection(_ source: BrowserInstalledImportSource) {
        guard !isImportSelectionLocked else { return }
        guard source.application == .otherChromium else {
            toggleImportSelection(source.application)
            return
        }
        let isChosen = selectedImportApplications.contains(.otherChromium)
        if isChosen, source.applicationURL != chosenUnlistedSourceURL {
            chosenUnlistedSourceURL = source.applicationURL
            return
        }
        chosenUnlistedSourceURL = isChosen ? nil : source.applicationURL
        toggleImportSelection(.otherChromium)
    }

    /// The browser `application` reads from: the listed one, or the found one chosen.
    func offeredSource(_ application: ImportSource) -> BrowserInstalledImportSource? {
        guard application == .otherChromium else {
            return installedSources.first { $0.application == application }
        }
        return unlistedSources.first { $0.applicationURL == chosenUnlistedSourceURL }
    }

    /// Stops what this Mac is doing for setup as the window goes. An import
    /// already applying finishes.
    func cancelOperations() {
        invalidateOperations()
        if state?.phase == .reading { send(CancelImportRead()) }
    }

    // MARK: - Actions - Steps

    func show(_ step: ImportStep) {
        guard !isImportSelectionLocked else { return }
        send(ShowImportStep(step: step))
    }

    // MARK: - Actions - Choosing browsers

    func toggleImportSelection(_ application: ImportSource) {
        guard !isImportSelectionLocked else { return }
        send(ToggleImportSource(source: application))
    }

    /// Reads the next selected browser after the core starts its import.
    func continueImportQueue() {
        guard !isImportSelectionLocked else { return }
        send(ContinueImport())
        readCurrentSource()
    }

    func cancelImportRead() {
        importReadCoordinator.cancel()
        isChoosingDataAccess = false
        send(CancelImportRead())
    }

    // MARK: - Actions - Reading

    /// Reads the browser the core is on, when it is reading one: from what a
    /// scan found, then a folder the person gave access to, then the browser's
    /// own folder when nothing has read it yet, and otherwise the folder the
    /// person picks.
    private func readCurrentSource() {
        guard let state, state.phase == .reading, let application = state.source else { return }
        guard let source = offeredSource(application) else {
            send(FailImport(source: application, reason: .sourceUnavailable, detail: nil))
            return
        }
        if source.hasReadableDetectedData, let payload = source.detectedPayload {
            readImport(payload)
            return
        }
        if let access = dataAccessProvider.resolve(for: application) {
            let data = application.importData(in: access.url)
            if !data.profiles.isEmpty {
                readImport(
                    BrowserDetectedImportPayload(application: application, data: data), activeDirectoryAccess: access)
                return
            }
            access.stopAccessing()
            dataAccessProvider.clear(for: application)
        }
        if source.detectedPayload == nil {
            let scanned = scannedSource(source)
            if scanned.hasReadableDetectedData, let payload = scanned.detectedPayload {
                readImport(payload)
                return
            }
        }
        chooseBrowserDataAccess(for: application)
    }

    /// `source` with its data folder read now, kept among the browsers setup
    /// offers.
    private func scannedSource(_ source: BrowserInstalledImportSource) -> BrowserInstalledImportSource {
        let scanned = sourceDiscovery.scanned(source)
        if let index = installedSources.firstIndex(where: { $0.id == source.id }) {
            installedSources[index] = scanned
        }
        return scanned
    }

    private func chooseBrowserDataAccess(for application: ImportSource) {
        isChoosingDataAccess = true
        let generation = operationGeneration
        dataAccessProvider.chooseDataFolder(for: application) { [weak self] folderURL in
            guard let self, operationGeneration == generation else { return }
            isChoosingDataAccess = false
            guard state?.phase == .reading, state?.source == application else { return }
            guard let folderURL else {
                send(CancelImportRead())
                return
            }
            let access = BrowserImportDataDirectoryAccess(url: folderURL)
            let data = application.importData(in: folderURL)
            guard !data.profiles.isEmpty else {
                access.stopAccessing()
                send(FailImport(source: application, reason: .dataFolder, detail: nil))
                return
            }
            try? dataAccessProvider.remember(folderURL, for: application)
            readImport(
                BrowserDetectedImportPayload(application: application, data: data), activeDirectoryAccess: access)
        }
    }

    private func readImport(
        _ payload: BrowserDetectedImportPayload,
        activeDirectoryAccess: BrowserImportDataDirectoryAccess? = nil
    ) {
        isChoosingDataAccess = false
        currentImportPayload = payload
        let generation = operationGeneration
        importReadCoordinator.startReading(
            payload,
            onFinish: { activeDirectoryAccess?.stopAccessing() },
            completion: { [weak self] result in
                guard let self, operationGeneration == generation else { return }
                completeRead(result, from: payload.application)
            })
    }

    /// Hands the core what the read brought, with where each of the
    /// browser's passwords belongs, or why it failed.
    private func completeRead(
        _ result: Result<BrowserImportReadOutput, any Error>, from application: ImportSource
    ) {
        do {
            let output = try result.get()
            extensionIcons.merge(output.extensionIcons.compactMapValues(NSImage.init(data:))) { _, read in read }
            _ = try browser.core.send(
                ReviewImport(
                    source: application, spaces: output.imported.map(\.seed),
                    // An engine that runs no extensions is offered none to install.
                    extensions: extensionInstaller == nil ? [] : output.extensions,
                    leftOut: output.leftOut,
                    title: offeredSource(application)?.title))
        } catch {
            send(FailImport(source: application, reason: .read, detail: error.personFacingDescription))
        }
    }

    // MARK: - Actions - Reviewing

    func setDestination(_ destination: BrowserImportDestination, for sourceSpaceID: UUID) {
        send(ChooseImportDestination(sourceSpaceID: sourceSpaceID, destinationSpaceID: destination.spaceID))
    }

    func setIncluded(_ tabID: UUID, _ isIncluded: Bool, in sourceSpaceID: UUID) {
        setIncluded([tabID], isIncluded, in: sourceSpaceID)
    }

    func setIncluded(_ tabIDs: Set<UUID>, _ isIncluded: Bool, in sourceSpaceID: UUID) {
        send(IncludeImportTabs(sourceSpaceID: sourceSpaceID, tabIDs: Array(tabIDs), included: isIncluded))
    }

    func setPlacement(_ placement: TabPlacement, for tabID: UUID, in sourceSpaceID: UUID) {
        send(PlaceImportTab(sourceSpaceID: sourceSpaceID, tabID: tabID, placement: placement))
    }

    func setSpaceIncluded(_ isIncluded: Bool, in sourceSpaceID: UUID) {
        send(IncludeImportSpace(sourceSpaceID: sourceSpaceID, included: isIncluded))
    }

    func setExtensionIncluded(_ extensionID: String, _ isIncluded: Bool, in sourceSpaceID: UUID) {
        send(IncludeImportExtension(sourceSpaceID: sourceSpaceID, extensionID: extensionID, included: isIncluded))
    }

    /// Turns every extension the reviewed Space `sourceSpaceID` offers on or off.
    func setExtensionsIncluded(_ isIncluded: Bool, in sourceSpaceID: UUID) {
        guard let review = reviewSpaces.first(where: { $0.id == sourceSpaceID }) else { return }
        for item in review.extensions where review.includedExtensionIDs.contains(item.extensionID) != isIncluded {
            setExtensionIncluded(item.extensionID, isIncluded, in: sourceSpaceID)
        }
    }

    /// Gives the reviewed Space `sourceSpaceID` `customization`, which the
    /// core keeps with its branding rules applied.
    func customize(_ sourceSpaceID: UUID, as customization: SpaceCustomization) {
        send(CustomizeImportSpace(sourceSpaceID: sourceSpaceID, customization: customization))
    }

    func selectedReview(id: UUID?) -> BrowserImportSpaceReview? {
        reviewSpaces.first { $0.id == id } ?? reviewSpaces.first
    }

    func reviewSummary() -> LocalizedStringResource? {
        review?.summary
    }

    /// What the core says the review's choices mean.
    func reviewAnalysis() -> BrowserImportReviewAnalysis {
        BrowserImportReviewAnalysis(review)
    }

    /// The session the review would leave. The core answers once each time
    /// the review changes.
    private func reviewPreview() -> BrowserSessionPreview? {
        guard let review else { return nil }
        if let previewCache, previewCache.review == review { return previewCache.session }
        let session = try? browser.reviewedImportPreview()
        previewCache = (review, session)
        return session
    }

    /// The images the tabs of the session the review would leave wear.
    var previewFavicons: FaviconAssets {
        reviewPreview()?.favicons ?? FaviconAssets()
    }

    func previewDestinationSpace(for review: BrowserImportSpaceReview) -> SpaceModel? {
        reviewPreview()?.space(id: review.destination.spaceID ?? review.id)
    }

    func customizationPreviewSpace(_ spaceID: UUID) -> SpaceModel? {
        reviewSpaces.first { $0.id == spaceID }.flatMap(previewDestinationSpace)
    }

    func duplicateDestinationName(for review: BrowserImportSpaceReview) -> String? {
        review.destination.spaceID.flatMap { browser.spaceModel($0)?.settings.name }
    }

    func destinationName(for destination: BrowserImportDestination) -> String {
        guard let spaceID = destination.spaceID else { return String(localized: "New Space") }
        return browser.spaceModel(spaceID)?.settings.name ?? String(localized: "Existing Space")
    }

    /// The workspace's Spaces, which a reviewed Space may join.
    var destinationSpaces: [SpaceModel] {
        browser.workspaceModel?.spaces.models ?? []
    }

    /// Whether the workspace is still the first launch's disposable Spaces.
    var hasDisposableSeedState: Bool {
        browser.workspaceModel?.isDisposableSeed ?? false
    }

    func reviewProgressLabel(for review: BrowserImportSpaceReview) -> String {
        let spaces = reviewSpaces
        let index = spaces.firstIndex(where: { $0.id == review.id }) ?? 0
        let spaceProgress = String(localized: "Space \(index + 1) of \(spaces.count)")
        guard let queue = state?.queue, queue.sources.count > 1, queue.current != nil else { return spaceProgress }
        let browserProgress = String(localized: "Browser \(queue.index + 1) of \(queue.sources.count)")
        return String(localized: "\(browserProgress) · \(spaceProgress)")
    }

    /// What reading `source` takes, or nil before setup has read its data.
    func importAccessLabel(for source: BrowserInstalledImportSource) -> String? {
        if source.hasReadableDetectedData, let payload = source.detectedPayload {
            let count = payload.profiles.count
            return count > 1
                ? String(localized: "\(count) profiles found · Review them")
                : String(localized: "Browser data found · Review it")
        }
        if dataAccessProvider.hasSavedAccess(for: source.application) {
            return String(localized: "Access saved · Ready to review")
        }
        guard source.detectedPayload != nil else { return nil }
        return String(localized: "One-time macOS permission · No folder search")
    }

    // MARK: - Actions - Importing

    /// Imports the review: the core applies it, and this reads and imports
    /// the passwords it brings. The core refuses a review that brings no Space.
    func commitReviewedImport() {
        guard let review, !isCommittingImport else { return }
        do {
            _ = try browser.core.send(BeginImportCommit())
            try browser.importReviewedSpaces()
            currentImportPayload = nil
            if let extensionInstaller, !review.extensionInstalls.isEmpty {
                extensionInstaller.installImported(review.extensionInstalls)
            }
            send(FinishImportCommit())
            readCurrentSource()
        } catch {
            send(FailImport(source: review.source, reason: .import, detail: error.personFacingDescription))
        }
    }

    // MARK: - Actions - Sending

    /// Sends `intent` to the core. A refused intent leaves setup as the core
    /// holds it.
    private func send(_ intent: some Intent) {
        _ = try? browser.core.send(intent)
    }

    private func invalidateOperations() {
        operationGeneration &+= 1
        importReadCoordinator.cancel()
        isChoosingDataAccess = false
    }

    private func abandonImportPreparation() {
        if isReading || isChoosingDataAccess {
            operationGeneration &+= 1
            importReadCoordinator.cancel()
            isChoosingDataAccess = false
        }
        if state?.phase == .reading { send(CancelImportRead()) }
    }
}
