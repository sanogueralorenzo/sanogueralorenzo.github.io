import Foundation
@preconcurrency import MediaPlayer
import XCTest

@testable import Crest

@MainActor
final class BrowserSystemNowPlayingTests: XCTestCase {

    func testCoordinatorPublishesStoreTruthRoutesCommandsAndClearsOnInvalidation() async throws {
        let store = BrowserMediaSessionStore()
        let endpoint = SystemNowPlayingFakeEndpoint()
        let driver = SystemNowPlayingFakeDriver()
        let coordinator = BrowserSystemNowPlayingCoordinator(
            store: store,
            driver: driver
        )
        let owner = BrowserTabRuntimeAssignment(
            tabID: UUID(),
            spaceID: UUID(),
            profileID: UUID()
        )
        let artwork = Data(repeating: 7, count: 32)
        coordinator.start()

        store.receive(
            BrowserMediaSessionPageEvent(
                documentIdentifier: "document",
                sequence: 1,
                location: "https://fixture.invalid/media",
                isInvalidated: false,
                hasActiveSession: true,
                title: "Track",
                artist: "Artist",
                album: "Album",
                artworkData: artwork,
                playbackState: .playing,
                isAudible: true,
                isMuted: false,
                availableActions: [.pause, .nextTrack]
            ),
            owner: owner,
            fallbackTitle: nil,
            endpoint: endpoint
        )
        try await waitUntil("the shared session to reach the system adapter") {
            driver.published.compactMap { $0 }.last?.title == "Track"
        }
        XCTAssertEqual(
            driver.published.compactMap { $0 }.last?.artworkData,
            artwork
        )
        XCTAssertTrue(driver.send(.pause))
        XCTAssertFalse(driver.send(.play))
        XCTAssertEqual(endpoint.actions, [.pause])

        store.invalidate(endpoint: endpoint)
        try await waitUntil("system Now Playing to clear after page invalidation") {
            driver.published.count >= 2 && driver.published.last! == nil
        }
        coordinator.stop()
        XCTAssertNil(driver.commandHandler)
    }

    private func waitUntil(
        _ description: String,
        timeout: Duration = .seconds(2),
        condition: () -> Bool
    ) async throws {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while ContinuousClock.now < deadline {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Timed out waiting for \(description).")
    }
}

@MainActor
private final class SystemNowPlayingFakeDriver: BrowserSystemNowPlayingDriving {
    private(set) var commandHandler: ((MediaSessionAction) -> Bool)?
    private(set) var published: [BrowserMediaSessionSnapshot?] = []

    func setCommandHandler(
        _ handler: ((MediaSessionAction) -> Bool)?
    ) {
        commandHandler = handler
    }

    func publish(_ session: BrowserMediaSessionSnapshot?) {
        published.append(session)
    }

    func send(_ action: MediaSessionAction) -> Bool {
        commandHandler?(action) == true
    }
}

@MainActor
private final class SystemNowPlayingFakeEndpoint: BrowserMediaSessionCommandEndpoint {
    private(set) var actions: [MediaSessionAction] = []

    func performMediaSessionAction(
        _ action: MediaSessionAction,
        documentIdentifier: String
    ) {
        actions.append(action)
    }

    func setMediaSessionMuted(
        _ muted: Bool,
        documentIdentifier: String
    ) {}
}
