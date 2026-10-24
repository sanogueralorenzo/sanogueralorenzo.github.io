import Foundation
import XCTest

@testable import Crest

@MainActor
final class BrowserSidebarWidgetRuntimeTests: XCTestCase {
    func testRegistryOrdersKindsThenInstancesAndShowsEveryProfileTogether() {
        let registry = BrowserSidebarWidgetRegistry(
            registrations: [.nowPlaying, .softwareUpdate]
        )
        let profileID = UUID()
        let otherProfileID = UUID()
        let firstSpace = UUID()
        let secondSpace = UUID()
        let foreignSpace = UUID()
        let first = nowPlayingInstance(
            tabID: UUID(),
            spaceID: firstSpace,
            profileID: profileID,
            ordinal: 2
        )
        let second = nowPlayingInstance(
            tabID: UUID(),
            spaceID: secondSpace,
            profileID: profileID,
            ordinal: 1
        )
        let foreign = nowPlayingInstance(
            tabID: UUID(),
            spaceID: foreignSpace,
            profileID: otherProfileID,
            ordinal: 0
        )
        let update = updateInstance(build: "599")

        let visible = registry.visibleInstances(
            from: [first, foreign, update, second],
            platform: .macOS,
            capabilities: [.persistentSidebar, .mediaSessions, .directSoftwareUpdates]
        )

        XCTAssertEqual(
            visible.map(\.id),
            [update.id, foreign.id, second.id, first.id],
            "Kind order first, then insertion ordinal, with no profile filtering."
        )
        XCTAssertEqual(
            visible.compactMap { instance -> UUID? in
                guard case .nowPlaying(let session) = instance.presentation
                else { return nil }
                return session.owner.spaceID
            },
            [foreignSpace, secondSpace, firstSpace],
            "The deck is one global layer: neither the active Space nor the active profile is part of visibility."
        )
    }

    func testRegistryFiltersPlatformCapabilitiesAndSingleInstanceKinds() {
        let registry = BrowserSidebarWidgetRegistry(
            registrations: [.nowPlaying, .softwareUpdate]
        )
        let updates = [updateInstance(build: "1"), updateInstance(build: "2")]

        XCTAssertTrue(
            registry.visibleInstances(
                from: updates,
                platform: .mobile,
                capabilities: [.persistentSidebar, .mediaSessions]
            ).isEmpty,
            "Mobile/App Store surfaces must not expose direct-distribution controls."
        )
        XCTAssertEqual(
            registry.visibleInstances(
                from: updates,
                platform: .macOS,
                capabilities: [.directSoftwareUpdates]
            ).count,
            1,
            "A single-instance registration cannot produce duplicate rows."
        )
    }

    func testRuntimePublishesEveryProfilesWidgetsToOneGlobalDeck() async {
        let source = FakeSidebarWidgetSource(kindID: .nowPlaying)
        let runtime = BrowserSidebarWidgetRuntime(
            registrations: [.nowPlaying],
            sources: [source]
        )
        let home = nowPlayingInstance(
            tabID: UUID(),
            spaceID: UUID(),
            profileID: UUID(),
            ordinal: 1
        )
        let work = nowPlayingInstance(
            tabID: UUID(),
            spaceID: UUID(),
            profileID: UUID(),
            ordinal: 2
        )

        runtime.activateHost(id: UUID(), capabilities: [.mediaSessions])
        await settle()
        source.send([home, work])
        await settle()

        XCTAssertEqual(
            runtime.instances(capabilities: [.mediaSessions]).map(\.id),
            [home.id, work.id],
            "Switching to a Space in another profile never removes the widget layer."
        )
    }

    func testWorkerLifecycleStartsOnceCancelsAtLastHostAndResumesFromAuthority() async {
        let source = FakeSidebarWidgetSource(kindID: .nowPlaying)
        let runtime = BrowserSidebarWidgetRuntime(
            registrations: [.nowPlaying],
            sources: [source]
        )
        let firstWindow = UUID()
        let secondWindow = UUID()

        runtime.activateHost(id: firstWindow, capabilities: [.mediaSessions])
        await settle()
        XCTAssertTrue(runtime.isWorkerRunning(for: .nowPlaying))
        XCTAssertEqual(source.subscriptionCount, 1)

        runtime.activateHost(id: firstWindow, capabilities: [.mediaSessions])
        runtime.activateHost(id: secondWindow, capabilities: [.mediaSessions])
        await settle()
        XCTAssertEqual(source.subscriptionCount, 1)

        runtime.suspendHost(id: firstWindow)
        XCTAssertTrue(runtime.isWorkerRunning(for: .nowPlaying))
        runtime.suspendHost(id: secondWindow)
        XCTAssertFalse(runtime.isWorkerRunning(for: .nowPlaying))
        await settle()
        XCTAssertEqual(source.terminationCount, 1)

        runtime.activateHost(id: secondWindow, capabilities: [.mediaSessions])
        await settle()
        XCTAssertTrue(runtime.isWorkerRunning(for: .nowPlaying))
        XCTAssertEqual(source.subscriptionCount, 2)
    }

    func testVisibilityPublishesOnlyDistinctStateAndSupportsMultipleInstances() async {
        let source = FakeSidebarWidgetSource(kindID: .nowPlaying)
        let runtime = BrowserSidebarWidgetRuntime(
            registrations: [.nowPlaying],
            sources: [source]
        )
        let profileID = UUID()
        let first = nowPlayingInstance(
            tabID: UUID(),
            spaceID: UUID(),
            profileID: profileID,
            ordinal: 1
        )
        let second = nowPlayingInstance(
            tabID: UUID(),
            spaceID: UUID(),
            profileID: profileID,
            ordinal: 2
        )

        runtime.activateHost(id: UUID(), capabilities: [.mediaSessions])
        await settle()
        source.send([first, second])
        await settle()
        XCTAssertEqual(runtime.visibilityRevision, 1)
        XCTAssertEqual(
            runtime.instances(capabilities: [.mediaSessions]).map(\.id),
            [first.id, second.id]
        )

        source.send([second, first])
        await settle()
        XCTAssertEqual(
            runtime.visibilityRevision,
            1,
            "Equivalent source emissions must not thrash sidebar layout."
        )

        source.send([])
        await settle()
        XCTAssertEqual(runtime.visibilityRevision, 2)
        XCTAssertTrue(runtime.publishedInstances.isEmpty)
    }

    func testCarouselSelectsNewestInstanceThenPreservesManualChoiceAcrossSpaces() async {
        let source = FakeSidebarWidgetSource(kindID: .nowPlaying)
        let runtime = BrowserSidebarWidgetRuntime(
            registrations: [.nowPlaying],
            sources: [source]
        )
        let profileID = UUID()
        let first = nowPlayingInstance(
            tabID: UUID(),
            spaceID: UUID(),
            profileID: profileID,
            ordinal: 1
        )
        let newest = nowPlayingInstance(
            tabID: UUID(),
            spaceID: UUID(),
            profileID: profileID,
            ordinal: 2
        )

        runtime.activateHost(id: UUID(), capabilities: [.mediaSessions])
        await settle()
        source.send([first])
        await settle()
        var visible = runtime.instances(capabilities: [.mediaSessions])
        runtime.reconcileCarouselSelection(visibleInstances: visible)
        XCTAssertEqual(runtime.carouselSelection, first.id)

        source.send([first, newest])
        await settle()
        visible = runtime.instances(capabilities: [.mediaSessions])
        runtime.reconcileCarouselSelection(visibleInstances: visible)
        XCTAssertEqual(
            runtime.carouselSelection,
            newest.id,
            "A newly registered widget becomes the centered carousel card."
        )

        runtime.selectCarouselInstance(
            first.id,
            visibleInstances: visible
        )
        runtime.reconcileCarouselSelection(visibleInstances: visible)
        XCTAssertEqual(
            runtime.carouselSelection,
            first.id,
            "One global selection: it does not reset merely because its owner belongs to another Space or profile."
        )
    }

    func testCarouselSelectionPrunesRemovedWidgetsAndFallsBackToARemainingCard() async {
        let source = FakeSidebarWidgetSource(kindID: .nowPlaying)
        let runtime = BrowserSidebarWidgetRuntime(
            registrations: [.nowPlaying],
            sources: [source]
        )
        let profileID = UUID()
        let first = nowPlayingInstance(
            tabID: UUID(),
            spaceID: UUID(),
            profileID: profileID,
            ordinal: 1
        )
        let second = nowPlayingInstance(
            tabID: UUID(),
            spaceID: UUID(),
            profileID: profileID,
            ordinal: 2
        )

        runtime.activateHost(id: UUID(), capabilities: [.mediaSessions])
        await settle()
        source.send([first, second])
        await settle()
        var visible = runtime.instances(capabilities: [.mediaSessions])
        runtime.reconcileCarouselSelection(visibleInstances: visible)
        runtime.selectCarouselInstance(
            first.id,
            visibleInstances: visible
        )
        XCTAssertEqual(runtime.carouselSelection, first.id)

        source.send([second])
        await settle()
        XCTAssertNil(
            runtime.carouselSelection,
            "Navigation or tab cleanup removes carousel state for the stale widget identity."
        )

        visible = runtime.instances(capabilities: [.mediaSessions])
        runtime.reconcileCarouselSelection(visibleInstances: visible)
        XCTAssertEqual(
            runtime.carouselSelection,
            second.id,
            "Losing the centered card falls back to a widget that is still visible."
        )
    }

    private func nowPlayingInstance(
        tabID: UUID,
        spaceID: UUID,
        profileID: UUID,
        ordinal: UInt64
    ) -> BrowserSidebarWidgetInstance {
        let sessionID = BrowserMediaSessionID(
            tabID: tabID,
            documentIdentifier: "document-\(ordinal)"
        )
        let snapshot = BrowserMediaSessionSnapshot(
            id: sessionID,
            owner: BrowserTabRuntimeAssignment(
                tabID: tabID,
                spaceID: spaceID,
                profileID: profileID
            ),
            ownerTitle: "Owner Tab \(ordinal)",
            title: "Track \(ordinal)",
            artist: nil,
            album: nil,
            artworkData: nil,
            playbackState: .playing,
            isAudible: true,
            isMuted: false,
            availableActions: [.pause],
            orderingOrdinal: ordinal
        )
        return BrowserSidebarWidgetInstance(
            id: BrowserSidebarWidgetID(
                kindID: .nowPlaying,
                instanceID: sessionID.id
            ),
            scope: .profile(profileID),
            orderingOrdinal: ordinal,
            presentation: .nowPlaying(snapshot),
            availableActions: [.activateOwner, .pause]
        )
    }

    private func updateInstance(build: String) -> BrowserSidebarWidgetInstance {
        BrowserSidebarWidgetInstance(
            id: BrowserSidebarWidgetID(
                kindID: .softwareUpdate,
                instanceID: build
            ),
            scope: .application,
            orderingOrdinal: 0,
            presentation: .softwareUpdate(
                BrowserSoftwareUpdateWidgetSnapshot(
                    phase: .available,
                    title: "Crest Update",
                    version: "0.5.0",
                    build: build,
                    releaseNotes: nil,
                    informationURL: nil,
                    message: nil,
                    progress: nil,
                    isInformationOnly: false,
                    allowsInstallation: true,
                    allowsSkipping: true,
                    allowsCancellation: false,
                    allowsInstallAndRelaunch: false,
                    allowsInstallationRetry: false,
                    isFixture: true
                )
            ),
            availableActions: [.installUpdate, .dismissExactUpdate]
        )
    }

    private func settle() async {
        for _ in 0..<4 { await Task.yield() }
    }
}

@MainActor
private final class FakeSidebarWidgetSource: BrowserSidebarWidgetEventSource {
    let kindID: BrowserSidebarWidgetKindID
    private(set) var subscriptionCount = 0
    private(set) var terminationCount = 0
    private var current: [BrowserSidebarWidgetInstance] = []
    private var continuations: [UUID: AsyncStream<[BrowserSidebarWidgetInstance]>.Continuation] = [:]

    init(kindID: BrowserSidebarWidgetKindID) {
        self.kindID = kindID
    }

    func events() -> AsyncStream<[BrowserSidebarWidgetInstance]> {
        subscriptionCount += 1
        let id = UUID()
        let (stream, continuation) = AsyncStream<[BrowserSidebarWidgetInstance]>.makeStream(
            bufferingPolicy: .bufferingNewest(1))
        continuations[id] = continuation
        continuation.onTermination = { @Sendable [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                continuations[id] = nil
                terminationCount += 1
            }
        }
        continuation.yield(current)
        return stream
    }

    func perform(
        _ action: BrowserSidebarWidgetAction,
        on instanceID: BrowserSidebarWidgetID
    ) {}

    func send(_ instances: [BrowserSidebarWidgetInstance]) {
        current = instances
        for continuation in continuations.values {
            continuation.yield(instances)
        }
    }
}
