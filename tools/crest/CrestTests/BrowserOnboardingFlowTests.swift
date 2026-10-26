import AppKit
import XCTest

@testable import Crest

@MainActor
final class BrowserOnboardingFlowTests: XCTestCase {
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

private enum TestFailure: LocalizedError {
    case read

    var errorDescription: String? { "The browser import could not be read." }
}
