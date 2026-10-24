import Foundation
import XCTest

@testable import Crest

final class BrowserTabStateArchiveTests: XCTestCase {

    func testEngineStateKeepsChromiumAcrossVersionsButRejectsOtherEnginesAndWebKitBuilds() throws {
        let payload = Data("opaque engine history".utf8)
        let chromium = try XCTUnwrap(
            BrowserEngineInteractionState(
                engine: .chromium, version: "1", payload: payload
            ).encoded())
        let webkit = try XCTUnwrap(
            BrowserEngineInteractionState(
                engine: .webKit, version: "os-1", payload: payload
            ).encoded())

        XCTAssertEqual(BrowserEngineInteractionState.payload(chromium, engine: .chromium, version: "1"), payload)
        XCTAssertEqual(
            BrowserEngineInteractionState.payload(chromium, engine: .chromium, version: "2"), payload,
            "Chromium reads back history another version of it saved, so an engine update keeps it.")
        XCTAssertEqual(BrowserEngineInteractionState.payload(webkit, engine: .webKit, version: "os-1"), payload)
        XCTAssertNil(BrowserEngineInteractionState.payload(webkit, engine: .webKit, version: "os-2"))
        XCTAssertNil(BrowserEngineInteractionState.payload(chromium, engine: .webKit, version: "1"))
        XCTAssertNil(BrowserEngineInteractionState.payload(webkit, engine: .chromium, version: "os-1"))
        XCTAssertNil(BrowserEngineInteractionState.payload(chromium.dropLast(), engine: .chromium, version: "1"))
        XCTAssertNil(BrowserEngineInteractionState.payload(chromium.dropLast(), engine: .webKit, version: "1"))
        XCTAssertEqual(BrowserEngineInteractionState.payload(payload, engine: .webKit, version: "os-1"), payload)
        XCTAssertNil(BrowserEngineInteractionState.payload(payload, engine: .chromium, version: "1"))
        XCTAssertNil(BrowserEngineInteractionState(engine: .chromium, version: "1", payload: Data()).encoded())
    }

    func testNamedReviewArchivesStaySeparateFromProductionAndEphemeralLaunches() throws {
        func environment(_ identity: String) -> BrowserLaunchEnvironment {
            BrowserLaunchEnvironment(
                values: [
                    "CREST_ISOLATED_SESSION": "1",
                    "CREST_ISOLATED_PERSISTENCE_ID": identity,
                ], isXCTestRuntime: false)
        }
        let first = try XCTUnwrap(BrowserTabStateArchive.forLaunch(environment("review-one")))
        let same = try XCTUnwrap(BrowserTabStateArchive.forLaunch(environment("review-one")))
        let other = try XCTUnwrap(BrowserTabStateArchive.forLaunch(environment("review-two")))
        XCTAssertEqual(first.rootDirectory, same.rootDirectory)
        XCTAssertNotEqual(first.rootDirectory, other.rootDirectory)
        XCTAssertNotEqual(first.rootDirectory, BrowserTabStateArchive.production()?.rootDirectory)
        XCTAssertNil(
            BrowserTabStateArchive.forLaunch(
                BrowserLaunchEnvironment(
                    values: ["CREST_ISOLATED_SESSION": "1"], isXCTestRuntime: false)))
        XCTAssertNil(
            BrowserTabStateArchive.forLaunch(
                BrowserLaunchEnvironment(
                    values: ["CREST_ISOLATED_PERSISTENCE_ID": "review-one"], isXCTestRuntime: true)))
        XCTAssertNil(
            BrowserTabStateArchive.forLaunch(
                BrowserLaunchEnvironment(
                    values: ["CREST_ISOLATED_PERSISTENCE_ID": "review-one"], isXCTestRuntime: false,
                    isSwiftUIPreviewRuntime: true)))
    }

    func testUntaggedStateFromAnotherOSBuildOrAnyStateInAnotherFormatIsNotRestorable() throws {
        let payload = Data("session".utf8)
        let taggedForeignBuild = try XCTUnwrap(
            BrowserTabStateEnvelope.decode(
                BrowserTabStateEnvelope(
                    interactionState: try XCTUnwrap(
                        BrowserEngineInteractionState(engine: .chromium, version: "1", payload: payload).encoded()),
                    url: nil,
                    osBuild: "Version 1.0 (Build 0A0)"
                ).encoded()
            )
        )
        let foreignBuild = try XCTUnwrap(
            BrowserTabStateEnvelope.decode(
                BrowserTabStateEnvelope(
                    interactionState: payload,
                    url: nil,
                    osBuild: "Version 1.0 (Build 0A0)"
                ).encoded()
            )
        )
        let foreignFormat = try XCTUnwrap(
            BrowserTabStateEnvelope.decode(
                BrowserTabStateEnvelope(
                    interactionState: payload,
                    url: nil,
                    formatVersion: BrowserTabStateEnvelope.currentFormatVersion + 1
                ).encoded()
            )
        )

        XCTAssertFalse(
            foreignBuild.isRestorable,
            "Untagged state is WebKit's private format, so another OS build must not be trusted."
        )
        XCTAssertTrue(
            taggedForeignBuild.isRestorable,
            "Tagged state carries its engine's own version check, so a macOS update keeps it."
        )
        XCTAssertFalse(foreignFormat.isRestorable)
    }

    func testTheCoresHistoryTravelsWithTheEngineStateAndEarlierFramesStillRestore() throws {
        let url = try XCTUnwrap(URL(string: "https://example.com/"))
        let state = Data("session".utf8)
        let history = Data("history".utf8)
        let current = try XCTUnwrap(
            BrowserTabStateEnvelope.decode(
                BrowserTabStateEnvelope(interactionState: state, url: url, history: history).encoded()))
        let earlier = try XCTUnwrap(
            BrowserTabStateEnvelope.decode(
                BrowserTabStateEnvelope(interactionState: state, url: url, history: history, formatVersion: 1)
                    .encoded()))

        XCTAssertEqual(current.history, history)
        XCTAssertEqual(current.interactionState, state)
        XCTAssertEqual(current.url, url)
        XCTAssertTrue(current.isRestorable)
        XCTAssertNil(earlier.history, "A version 1 frame, as earlier builds wrote it, carries no history.")
        XCTAssertEqual(earlier.interactionState, state)
        XCTAssertTrue(earlier.isRestorable)

        // A page with no engine state yet still keeps the core's history.
        let historyOnly = try XCTUnwrap(
            BrowserTabStateEnvelope.decode(
                BrowserTabStateEnvelope(interactionState: Data(), url: url, history: history).encoded()))
        XCTAssertEqual(historyOnly.history, history)
        XCTAssertTrue(historyOnly.isReadable)
        XCTAssertFalse(historyOnly.isRestorable, "An empty engine state is never handed to the engine.")
    }

    func testUnframedOrTruncatedDataDecodesToNothing() throws {
        let encoded = BrowserTabStateEnvelope(
            interactionState: Data("session".utf8),
            url: try XCTUnwrap(URL(string: "https://example.com/"))
        ).encoded()

        XCTAssertNil(BrowserTabStateEnvelope.decode(Data()))
        XCTAssertNil(BrowserTabStateEnvelope.decode(Data("not an envelope at all".utf8)))
        XCTAssertNil(
            BrowserTabStateEnvelope.decode(encoded.prefix(8)),
            "A file cut short must not decode into a partial session."
        )
        XCTAssertNil(
            BrowserTabStateEnvelope.decode(encoded.dropLast(encoded.count - 14)),
            "A header promising more bytes than the file holds must be refused."
        )
    }

    func testRestorePolicyKeepsFragmentDriftAndRefusesADifferentDestination() throws {
        let archived = try XCTUnwrap(URL(string: "https://example.com/doc#section-2"))
        let sameDocument = try XCTUnwrap(URL(string: "https://example.com/doc"))
        let otherQuery = try XCTUnwrap(URL(string: "https://example.com/doc?revision=2"))
        let otherHost = try XCTUnwrap(URL(string: "https://elsewhere.example/doc"))

        XCTAssertTrue(
            SamePage.restoresArchivedState(
                archivedURL: archived,
                tabURL: sameDocument
            )
        )
        XCTAssertTrue(
            SamePage.restoresArchivedState(
                archivedURL: archived,
                tabURL: archived
            )
        )
        XCTAssertFalse(
            SamePage.restoresArchivedState(
                archivedURL: archived,
                tabURL: otherQuery
            ),
            "A tab pointed somewhere else while unloaded must win over its old state."
        )
        XCTAssertFalse(
            SamePage.restoresArchivedState(
                archivedURL: archived,
                tabURL: otherHost
            )
        )
        XCTAssertFalse(
            SamePage.restoresArchivedState(
                archivedURL: nil,
                tabURL: sameDocument
            )
        )
    }

    func testArchivedStateIsReadableBackAndDeletablePerTab() async throws {
        let archive = try makeArchive()
        let profileID = UUID()
        let first = UUID()
        let second = UUID()
        let url = try XCTUnwrap(URL(string: "https://example.com/one"))

        archive.archive(
            interactionState: Data("first".utf8),
            url: url,
            history: nil,
            profileID: profileID,
            tabID: first
        )
        archive.archive(
            interactionState: Data("second".utf8),
            url: url,
            history: nil,
            profileID: profileID,
            tabID: second
        )
        await archive.flushPendingWrites()

        XCTAssertEqual(
            BrowserTabStateEnvelope.decode(
                try XCTUnwrap(archive.archivedState(profileID: profileID, tabID: first))
            )?.interactionState,
            Data("first".utf8)
        )

        archive.removeState(profileID: profileID, tabID: first)
        await archive.flushPendingWrites()

        XCTAssertNil(archive.archivedState(profileID: profileID, tabID: first))
        XCTAssertNotNil(archive.archivedState(profileID: profileID, tabID: second))
    }

    func testAnEmptyStateIsNeverWritten() async throws {
        let archive = try makeArchive()
        let profileID = UUID()
        let tabID = UUID()

        archive.archive(
            interactionState: Data(),
            url: nil,
            history: nil,
            profileID: profileID,
            tabID: tabID
        )
        await archive.flushPendingWrites()

        XCTAssertNil(archive.archivedState(profileID: profileID, tabID: tabID))
    }

    func testAnOversizedStateIsDroppedAndTakesAnyStaleStateWithIt() async throws {
        let archive = try makeArchive(maximumStateByteCount: 512)
        let profileID = UUID()
        let tabID = UUID()
        let url = try XCTUnwrap(URL(string: "https://example.com/one"))

        archive.archive(
            interactionState: Data("small".utf8),
            url: url,
            history: nil,
            profileID: profileID,
            tabID: tabID
        )
        await archive.flushPendingWrites()
        XCTAssertNotNil(archive.archivedState(profileID: profileID, tabID: tabID))

        archive.archive(
            interactionState: Data(repeating: 0xAB, count: 4096),
            url: url,
            history: nil,
            profileID: profileID,
            tabID: tabID
        )
        await archive.flushPendingWrites()

        XCTAssertNil(
            archive.archivedState(profileID: profileID, tabID: tabID),
            "An oversized state must not leave an older one behind to restore instead."
        )
    }

    func testAProfileKeepsOnlyItsMostRecentlyWrittenStates() async throws {
        let archive = try makeArchive(maximumStatesPerProfile: 3)
        let profileID = UUID()
        let url = try XCTUnwrap(URL(string: "https://example.com/one"))
        var tabIDs: [UUID] = []

        for index in 0..<5 {
            let tabID = UUID()
            tabIDs.append(tabID)
            archive.archive(
                interactionState: Data("state-\(index)".utf8),
                url: url,
                history: nil,
                profileID: profileID,
                tabID: tabID
            )
            await archive.flushPendingWrites()
            // Modification dates order the eviction, and APFS timestamps are not
            // fine-grained enough to separate writes issued back to back.
            try await Task.sleep(for: .milliseconds(20))
        }

        let retained = tabIDs.filter {
            archive.archivedState(profileID: profileID, tabID: $0) != nil
        }
        XCTAssertEqual(retained, Array(tabIDs.suffix(3)))
    }

    func testRemovingAProfileLeavesEveryOtherProfileAlone() async throws {
        let archive = try makeArchive()
        let deleted = UUID()
        let kept = UUID()
        let deletedTab = UUID()
        let keptTab = UUID()
        let url = try XCTUnwrap(URL(string: "https://example.com/one"))

        archive.archive(
            interactionState: Data("gone".utf8),
            url: url,
            history: nil,
            profileID: deleted,
            tabID: deletedTab
        )
        archive.archive(
            interactionState: Data("stays".utf8),
            url: url,
            history: nil,
            profileID: kept,
            tabID: keptTab
        )
        await archive.flushPendingWrites()

        archive.removeStates(profileID: deleted)
        await archive.flushPendingWrites()

        XCTAssertNil(archive.archivedState(profileID: deleted, tabID: deletedTab))
        XCTAssertNotNil(archive.archivedState(profileID: kept, tabID: keptTab))
    }

    func testPruningKeepsKnownTabsAndSkipsProfilesItWasNotToldAbout() async throws {
        let archive = try makeArchive()
        let swept = UUID()
        let untouched = UUID()
        let keptTab = UUID()
        let deletedTab = UUID()
        let otherProfileTab = UUID()
        let url = try XCTUnwrap(URL(string: "https://example.com/one"))

        for (profileID, tabID) in [
            (swept, keptTab),
            (swept, deletedTab),
            (untouched, otherProfileTab),
        ] {
            archive.archive(
                interactionState: Data("state".utf8),
                url: url,
                history: nil,
                profileID: profileID,
                tabID: tabID
            )
        }
        await archive.flushPendingWrites()

        archive.pruneStates(keeping: [swept: [keptTab]])
        await archive.flushPendingWrites()

        XCTAssertNotNil(archive.archivedState(profileID: swept, tabID: keptTab))
        XCTAssertNil(archive.archivedState(profileID: swept, tabID: deletedTab))
        XCTAssertNotNil(
            archive.archivedState(profileID: untouched, tabID: otherProfileTab),
            "A sweep must not reach profiles outside the session it was given."
        )
    }

    private func makeArchive(
        maximumStateByteCount: Int = BrowserTabStateArchive.defaultMaximumStateByteCount,
        maximumStatesPerProfile: Int = BrowserTabStateArchive.defaultMaximumStatesPerProfile
    ) throws -> BrowserTabStateArchive {
        let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("crest-tab-state-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: root)
        }
        return BrowserTabStateArchive(
            rootDirectory: root,
            maximumStateByteCount: maximumStateByteCount,
            maximumStatesPerProfile: maximumStatesPerProfile
        )
    }
}

/// The favicon side store the session core no longer carries bytes for.
final class BrowserFaviconFileStoreTests: XCTestCase {
    func testAnIconRoundTripsForItsOwnTab() async throws {
        let store = try makeStore()
        let tabID = UUID()
        let icon = Data("icon".utf8)

        store.reconcile(icon, tabID: tabID)
        await store.flushPendingWrites()

        XCTAssertEqual(store.favicon(tabID: tabID), icon)
        XCTAssertNil(store.favicon(tabID: UUID()))
    }

    func testIdenticalBytesAreNotRewritten() async throws {
        let store = try makeStore()
        let tabID = UUID()
        let icon = Data("steady".utf8)
        store.reconcile(icon, tabID: tabID)
        await store.flushPendingWrites()
        let firstIdentity = try fileIdentity(of: store.faviconFileURL(tabID: tabID))

        store.reconcile(icon, tabID: tabID)
        await store.flushPendingWrites()

        XCTAssertEqual(
            try fileIdentity(of: store.faviconFileURL(tabID: tabID)),
            firstIdentity,
            "An unchanged icon must not cost a write; an atomic write replaces the file."
        )

        store.reconcile(Data("changed".utf8), tabID: tabID)
        await store.flushPendingWrites()

        XCTAssertNotEqual(
            try fileIdentity(of: store.faviconFileURL(tabID: tabID)),
            firstIdentity
        )
        XCTAssertEqual(store.favicon(tabID: tabID), Data("changed".utf8))
    }

    func testATabWithoutANewIconKeepsTheOneItHad() async throws {
        let store = try makeStore()
        let tabID = UUID()
        let icon = Data("cached".utf8)
        store.reconcile(icon, tabID: tabID)
        await store.flushPendingWrites()

        store.reconcile(nil, tabID: tabID)
        await store.flushPendingWrites()

        XCTAssertEqual(store.favicon(tabID: tabID), icon)
    }

    func testAnOversizedIconIsIgnoredAndKeepsTheLastValidIcon() async throws {
        let store = try makeStore(maximumFaviconByteCount: 8)
        let tabID = UUID()
        let icon = Data("small".utf8)
        store.reconcile(icon, tabID: tabID)
        await store.flushPendingWrites()

        store.reconcile(Data(repeating: 7, count: 64), tabID: tabID)
        await store.flushPendingWrites()

        XCTAssertEqual(
            store.favicon(tabID: tabID),
            icon,
            "An invalid capture must not erase the last valid icon for a live tab."
        )
    }

    func testPruningKeepsOnlyTheTabsTheSessionStillHas() async throws {
        let store = try makeStore()
        let kept = UUID()
        let dropped = UUID()
        store.reconcile(Data("kept".utf8), tabID: kept)
        store.reconcile(Data("dropped".utf8), tabID: dropped)
        await store.flushPendingWrites()

        store.pruneFavicons(keeping: [kept])
        await store.flushPendingWrites()

        XCTAssertEqual(store.favicon(tabID: kept), Data("kept".utf8))
        XCTAssertNil(store.favicon(tabID: dropped))
    }

    private func fileIdentity(of url: URL) throws -> UInt64 {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return try XCTUnwrap(attributes[.systemFileNumber] as? UInt64)
    }

    private func makeStore(
        maximumFaviconByteCount: Int = BrowserFaviconFileStore.defaultMaximumFaviconByteCount
    ) throws -> BrowserFaviconFileStore {
        let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("crest-favicons-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: root)
        }
        return BrowserFaviconFileStore(
            rootDirectory: root,
            maximumFaviconByteCount: maximumFaviconByteCount
        )
    }
}
