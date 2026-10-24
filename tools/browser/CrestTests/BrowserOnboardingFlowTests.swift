import AppKit
import XCTest

@testable import Crest

@MainActor
final class BrowserOnboardingFlowTests: XCTestCase {
    func testAFailedReadRetriesAndTheReviewedImportLandsInTheSession() async throws {
        let reader = SequencedImportReader(
            results: [
                .failure(TestFailure.read),
                .success(readOutput(application: .safari, spaces: [makeSpace(name: "Imported")])),
            ]
        )
        let flow = makeFlow(sourceDiscovery: StubSourceDiscovery(sources: [source(.safari)]), reader: reader)
        flow.start()
        flow.discoverInstalledSources()
        flow.toggleImportSelection(.safari)

        flow.continueImportQueue()
        await waitUntil { flow.failure != nil }
        XCTAssertEqual(flow.step, .importBrowser)
        XCTAssertEqual(flow.failure?.message, .verbatim(TestFailure.read.localizedDescription))
        XCTAssertEqual(flow.selectedImportApplications, [.safari])

        flow.continueImportQueue()
        await waitUntil { flow.step == .review }
        XCTAssertNil(flow.failure)
        let readCount = await reader.readCount
        XCTAssertEqual(readCount, 2)

        flow.commitReviewedImport()
        await waitUntil { flow.step == .complete }
        XCTAssertEqual(flow.browser.spaceModels.filter { $0.settings.name == "Imported" }.count, 1)
    }

    /// The extensions a review leaves on, and only those, go to the installer
    /// once the import has made their Space.
    func testExtensionsLeftOnAreHandedToTheInstallerWhenTheImportLands() async throws {
        let (first, second) = ("cjpalhdlnbpafiamejdnhcphjbkeiagm", "eimadpbcbfnmbkopoojfekhnkhdbieeh")
        var output = readOutput(application: .chrome, spaces: [makeSpace(name: "Extension Import Space")])
        let spaceID = try XCTUnwrap(output.imported.first?.id)
        output.extensions = [
            ImportSpaceExtensions(
                spaceID: spaceID,
                extensions: [
                    ImportExtension(extensionID: first, name: "uBlock Origin"),
                    ImportExtension(extensionID: second, name: "Dark Reader"),
                ])
        ]
        let installer = RecordingExtensionInstaller()
        let flow = makeFlow(
            sourceDiscovery: StubSourceDiscovery(sources: [source(.chrome)]),
            reader: SequencedImportReader(results: [.success(output)]),
            extensionInstaller: installer)
        flow.start()
        flow.discoverInstalledSources()
        flow.toggleImportSelection(.chrome)
        flow.continueImportQueue()
        await waitUntil { flow.step == .review }
        XCTAssertEqual(flow.review?.includedExtensionCount, 2)

        flow.setExtensionIncluded(second, false, in: spaceID)
        XCTAssertEqual(flow.review?.includedExtensionCount, 1)
        XCTAssertTrue(installer.installs.isEmpty)

        flow.commitReviewedImport()
        await waitUntil { flow.step == .complete }
        XCTAssertEqual(
            installer.installs,
            [[ImportExtensionInstall(extensionID: first, name: "uBlock Origin", iconPath: nil, spaceIDs: [spaceID])]])
    }

    /// Setup reads no browser's data until the person asks: opening it lists
    /// the browsers by their apps, and going on with one reads that one alone.
    func testSetupReadsOnlyTheBrowserThePersonGoesOnWith() async {
        let discovery = RecordingSourceDiscovery(read: [source(.chrome), source(.arc)])
        let flow = makeFlow(
            sourceDiscovery: discovery,
            reader: SequencedImportReader(
                results: [.success(readOutput(application: .chrome, spaces: [makeSpace(name: "Chrome")]))]))
        flow.start()
        flow.discoverInstalledSources()
        XCTAssertEqual(flow.offeredSources.map(\.application), [.chrome, .arc])
        XCTAssertTrue(discovery.readApplications.isEmpty)

        flow.toggleImportSelection(.chrome)
        flow.continueImportQueue()
        await waitUntil { flow.step == .review }
        XCTAssertEqual(discovery.readApplications, [.chrome])
    }

    func testCancellationPreventsALateReadFromPublishingAReview() async {
        let reader = SuspendedFlowImportReader()
        let flow = makeFlow(sourceDiscovery: StubSourceDiscovery(sources: [source(.arc)]), reader: reader)
        flow.start()
        flow.discoverInstalledSources()
        flow.toggleImportSelection(.arc)
        flow.continueImportQueue()
        await reader.waitUntilStarted()

        flow.cancelImportRead()
        await reader.complete(readOutput(application: .arc, spaces: [makeSpace(name: "Too Late")]))
        await Task.yield()

        XCTAssertEqual(flow.step, .importBrowser)
        XCTAssertEqual(flow.state?.phase, .idle)
        XCTAssertNil(flow.review)
        XCTAssertNil(flow.failure)
    }

    /// An import that has begun applying finishes, whatever the window does
    /// meanwhile; the reset it held back runs after it.
    func testResetDuringFinalizationLetsTheCommittedImportFinish() async {
        let committer = PostMutationSuspendedImportCommitter()
        let flow = makeFlow(
            sourceDiscovery: StubSourceDiscovery(sources: [source(.safari)]),
            reader: SequencedImportReader(
                results: [
                    .success(readOutput(application: .safari, spaces: [makeSpace(name: "Committed Before Reset")]))
                ]),
            importCommitter: committer
        )
        flow.start()
        flow.discoverInstalledSources()
        flow.toggleImportSelection(.safari)
        flow.continueImportQueue()
        await waitUntil { flow.step == .review }
        flow.commitReviewedImport()
        await committer.waitUntilFinalizationStarted()
        XCTAssertTrue(flow.browser.spaceModels.contains { $0.settings.name == "Committed Before Reset" })

        flow.reset(for: BrowserOnboardingRequest(entryPoint: .manualSetup))
        XCTAssertTrue(flow.isCommittingImport)

        committer.completeFinalization()
        await waitUntil { !flow.isCommittingImport && flow.step == .manualSetup }
        XCTAssertNil(flow.failure)
        XCTAssertTrue(flow.browser.spaceModels.contains { $0.settings.name == "Committed Before Reset" })
    }

    private func makeFlow(
        sourceDiscovery: any BrowserInstalledImportSourceDiscovering,
        reader: any BrowserOnboardingImportReading,
        importCommitter: any BrowserOnboardingImportCommitting = LiveBrowserOnboardingImportCommitter(),
        extensionInstaller: (any BrowserImportedExtensionInstalling)? = nil
    ) -> BrowserOnboardingFlow {
        BrowserOnboardingFlow(
            request: BrowserOnboardingRequest(entryPoint: .importBrowser),
            browser: BrowserStore(seed: .preview),
            sourceDiscovery: sourceDiscovery,
            dataAccessProvider: StubDataAccessProvider(),
            importReader: reader,
            importCommitter: importCommitter,
            extensionInstaller: extensionInstaller
        )
    }

    private func source(
        _ application: ImportSource,
        hasDetectedData: Bool = true,
        detectedDataURL: URL? = nil
    ) -> BrowserInstalledImportSource {
        BrowserInstalledImportSource(
            application: application,
            applicationURL: URL(fileURLWithPath: "/Applications/\(application.title).app"),
            detectedPayload: BrowserDetectedImportPayload(
                application: application,
                profiles: [
                    ImportProfile(
                        id: "Default",
                        name: "Default",
                        bookmarksPath: hasDetectedData
                            ? (detectedDataURL ?? URL(fileURLWithPath: #filePath)).path
                            : nil,
                        sessionPath: nil
                    )
                ]
            ),
            icon: NSImage(size: NSSize(width: 64, height: 64))
        )
    }

    private func makeSpace(name: String) -> SpaceState.Seed {
        let tab = TabState.Seed(
            title: "Example",
            url: URL(string: "https://example.com"),
            placement: .current
        )
        return SpaceState.Seed(name: name, symbol: "square.and.arrow.down", accent: .indigo, tabs: [tab])
    }

    /// What reading `application` brings: `spaces`, as the core holds them.
    private func readOutput(
        application: ImportSource,
        spaces: [SpaceState.Seed]
    ) -> BrowserOnboardingImportReadOutput {
        BrowserOnboardingImportReadOutput(
            payload: BrowserDetectedImportPayload(application: application, profiles: []),
            imported: BrowserStore(seed: SessionState.Seed(spaces: spaces)).snapshot.spaces,
            passwordCandidates: []
        )
    }

    private func waitUntil(
        timeout: Duration = .seconds(2),
        predicate: @MainActor () -> Bool
    ) async {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            if predicate() { return }
            await Task.yield()
        }
        XCTFail("Timed out waiting for onboarding flow state")
    }

}

@MainActor
private struct StubSourceDiscovery: BrowserInstalledImportSourceDiscovering {
    let sources: [BrowserInstalledImportSource]

    func installedSources() -> [BrowserInstalledImportSource] {
        sources
    }
}

/// Lists the browsers by their apps alone and records each one setup reads.
@MainActor
private final class RecordingSourceDiscovery: BrowserInstalledImportSourceDiscovering {
    private let read: [BrowserInstalledImportSource]
    private(set) var readApplications: [ImportSource] = []

    init(read: [BrowserInstalledImportSource]) {
        self.read = read
    }

    func installedSources() -> [BrowserInstalledImportSource] {
        read.map {
            BrowserInstalledImportSource(application: $0.application, applicationURL: $0.applicationURL, icon: $0.icon)
        }
    }

    func scanned(_ source: BrowserInstalledImportSource) -> BrowserInstalledImportSource {
        readApplications.append(source.application)
        return read.first { $0.id == source.id } ?? source
    }
}

@MainActor
private final class RecordingExtensionInstaller: BrowserImportedExtensionInstalling {
    private(set) var installs: [[ImportExtensionInstall]] = []

    func installImported(_ installs: [ImportExtensionInstall]) {
        self.installs.append(installs)
    }
}

private struct StubDataAccessProvider: BrowserOnboardingDataAccessProviding {
    func resolve(
        for application: ImportSource
    ) -> BrowserImportDataDirectoryAccess? {
        nil
    }

    func clear(for application: ImportSource) {}

    func remember(
        _ directoryURL: URL,
        for application: ImportSource
    ) throws {}

    func chooseDataFolder(
        for application: ImportSource,
        completion: @escaping @MainActor (URL?) -> Void
    ) {
        completion(nil)
    }

    func hasSavedAccess(for application: ImportSource) -> Bool {
        false
    }
}

@MainActor
private final class PostMutationSuspendedImportCommitter:
    BrowserOnboardingImportCommitting
{
    private var finalizationContinuation: CheckedContinuation<Void, Never>?
    private var finalizationStartWaiters: [CheckedContinuation<Void, Never>] = []

    func prepare(
        review: SetupImportReview,
        payload: BrowserDetectedImportPayload?
    ) async throws -> BrowserOnboardingPreparedImport {
        BrowserOnboardingPreparedImport(passwords: [])
    }

    func finalize(
        review: SetupImportReview,
        preparedImport: BrowserOnboardingPreparedImport,
        browser: BrowserStore
    ) async throws -> BrowserPasswordImportResult {
        try browser.importReviewedSpaces()
        await withCheckedContinuation { continuation in
            finalizationContinuation = continuation
            for waiter in finalizationStartWaiters {
                waiter.resume()
            }
            finalizationStartWaiters.removeAll()
        }
        return .empty
    }

    func waitUntilFinalizationStarted() async {
        guard finalizationContinuation == nil else { return }
        await withCheckedContinuation { continuation in
            finalizationStartWaiters.append(continuation)
        }
    }

    func completeFinalization() {
        finalizationContinuation?.resume()
        finalizationContinuation = nil
    }
}

private actor SequencedImportReader: BrowserOnboardingImportReading {
    private var results: [Result<BrowserOnboardingImportReadOutput, TestFailure>]
    private(set) var readCount = 0

    init(results: [Result<BrowserOnboardingImportReadOutput, TestFailure>]) {
        self.results = results
    }

    func read(
        _ payload: BrowserDetectedImportPayload
    ) async throws -> BrowserOnboardingImportReadOutput {
        readCount += 1
        return try results.removeFirst().get()
    }
}

private actor SuspendedFlowImportReader: BrowserOnboardingImportReading {
    private var continuation:
        CheckedContinuation<
            BrowserOnboardingImportReadOutput,
            Error
        >?
    private var startWaiters: [CheckedContinuation<Void, Never>] = []

    func read(
        _ payload: BrowserDetectedImportPayload
    ) async throws -> BrowserOnboardingImportReadOutput {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            for waiter in startWaiters {
                waiter.resume()
            }
            startWaiters.removeAll()
        }
    }

    func waitUntilStarted() async {
        guard continuation == nil else { return }
        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }

    func complete(_ output: BrowserOnboardingImportReadOutput) {
        continuation?.resume(returning: output)
        continuation = nil
    }
}

private enum TestFailure: LocalizedError {
    case read

    var errorDescription: String? { "The browser import could not be read." }
}
