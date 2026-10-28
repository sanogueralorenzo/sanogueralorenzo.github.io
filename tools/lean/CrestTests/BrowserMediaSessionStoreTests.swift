import XCTest

@testable import Crest

@MainActor
final class BrowserMediaSessionStoreTests: XCTestCase {
    func testStaleAndRetiredDocumentsCannotPublishOrTakeCommands() throws {
        let store = BrowserMediaSessionStore()
        let owner = assignment()
        let endpoint = Endpoint()
        receive(store, owner, endpoint, sequence: 1)
        let original = try XCTUnwrap(store.sessions.first)
        receive(store, owner, Endpoint(), sequence: 1, playback: .paused)
        XCTAssertEqual(store.sessions, [original])
        store.perform(.pause, on: original.id)
        XCTAssertEqual(endpoint.actions, [.pause])

        receive(store, owner, endpoint, sequence: 2, invalidated: true)
        receive(store, owner, endpoint, sequence: 3)
        XCTAssertTrue(store.sessions.isEmpty)
        XCTAssertTrue(store.sidebarSessions.isEmpty)
    }

    func testNewDocumentSupersedesOnlyThePreviousDocumentInItsTab() throws {
        let store = BrowserMediaSessionStore()
        let owner = assignment()
        let other = assignment()
        let endpoint = Endpoint()
        receive(store, owner, endpoint, sequence: 1)
        receive(store, other, endpoint, sequence: 1)
        let oldID = try XCTUnwrap(store.sessions.first).id
        receive(store, owner, endpoint, sequence: 1, document: "new-document")
        XCTAssertEqual(store.sessions.map(\.owner), [other, owner])
        receive(store, owner, endpoint, sequence: 99)
        XCTAssertFalse(store.sessions.contains { $0.id == oldID })
        XCTAssertEqual(store.sessions.count, 2)
    }

    func testDismissalHidesOnlyTheCardUntilPlaybackStartsAgain() throws {
        let store = BrowserMediaSessionStore()
        let owner = assignment()
        let endpoint = Endpoint()
        receive(store, owner, endpoint, sequence: 1)
        let id = try XCTUnwrap(store.sessions.first).id
        store.dismissCard(of: id)
        receive(store, owner, endpoint, sequence: 2)
        XCTAssertTrue(store.sidebarSessions.isEmpty)
        XCTAssertNotNil(store.session(of: owner))
        receive(store, owner, endpoint, sequence: 3, playback: .paused)
        XCTAssertTrue(store.sidebarSessions.isEmpty)
        receive(store, owner, endpoint, sequence: 4)
        XCTAssertEqual(store.sidebarSessions.map(\.id), [id])
    }

    func testUncontrollableSoundGetsNoCardButAnExistingMutedPlayerKeepsItsCard() throws {
        let store = BrowserMediaSessionStore()
        let owner = assignment()
        let endpoint = Endpoint()
        receive(store, owner, endpoint, sequence: 1, actions: [])
        XCTAssertTrue(store.sessions.isEmpty)
        receive(store, owner, endpoint, sequence: 2)
        let ordinal = try XCTUnwrap(store.sessions.first).orderingOrdinal
        receive(store, owner, endpoint, sequence: 3, muted: true, actions: [])
        XCTAssertEqual(store.sessions.first?.orderingOrdinal, ordinal)
        XCTAssertEqual(store.sessions.first?.isMuted, true)
        receive(store, owner, endpoint, sequence: 4, actions: [])
        XCTAssertTrue(store.sessions.isEmpty)
        receive(store, owner, endpoint, sequence: 5)
        XCTAssertEqual(store.sessions.first?.orderingOrdinal, ordinal)
    }

    func testEndpointInvalidationDoesNotRetireItsReplacement() throws {
        let store = BrowserMediaSessionStore()
        let owner = assignment()
        let old = Endpoint()
        let replacement = Endpoint()
        receive(store, owner, old, sequence: 1)
        receive(store, owner, replacement, sequence: 2)
        store.invalidate(owner: owner, endpoint: old)
        XCTAssertEqual(store.sessions.count, 1)
        store.invalidate(endpoint: replacement)
        receive(store, owner, replacement, sequence: 3)
        XCTAssertTrue(store.sessions.isEmpty)
    }

    func testRetiredIdentityWindowRemainsBounded() {
        let store = BrowserMediaSessionStore()
        let owner = assignment()
        let endpoint = Endpoint()
        receive(store, owner, endpoint, sequence: 1)
        receive(store, owner, endpoint, sequence: 2, invalidated: true)
        for index in 0..<512 {
            receive(store, owner, endpoint, sequence: 1, document: "retired-\(index)", invalidated: true)
        }
        // An evicted identity starts afresh; a still-retained retired one cannot.
        receive(store, owner, endpoint, sequence: 3, document: "retired-511")
        XCTAssertTrue(store.sessions.isEmpty)
        receive(store, owner, endpoint, sequence: 3)
        XCTAssertEqual(store.sessions.first?.id.documentIdentifier, "document")
    }

    func testNowPlayingPrefersPlayingThenAudibleThenMostRecentlyPublished() throws {
        let store = BrowserMediaSessionStore()
        let older = assignment()
        let newer = assignment()
        let newest = assignment()
        let endpoint = Endpoint()
        receive(store, older, endpoint, sequence: 1, audible: true)
        receive(store, newer, endpoint, sequence: 1, audible: false)
        receive(store, newest, endpoint, sequence: 1, playback: .paused, audible: true)
        XCTAssertEqual(arbitration(store)?.nowPlaying?.owner, older)
        receive(store, newer, endpoint, sequence: 2, audible: true)
        XCTAssertEqual(arbitration(store)?.nowPlaying?.owner, newer)
        receive(store, newest, endpoint, sequence: 2, audible: true)
        XCTAssertEqual(arbitration(store)?.nowPlaying?.owner, newest)
        XCTAssertEqual(arbitration(store)?.order.map(\.owner), [older, newer, newest])
        receive(store, newest, endpoint, sequence: 3, playback: .none, audible: true)
        XCTAssertEqual(arbitration(store)?.nowPlaying?.owner, newer)
        let one = try XCTUnwrap(store.sessions.first)
        XCTAssertNil(BrowserMediaSessionOrdering.arbitration(of: [one, one]))
    }

    func testArbitrationLimitKeepsAllCardsPublished() {
        let store = BrowserMediaSessionStore()
        let endpoint = Endpoint()
        for _ in 0..<65 { receive(store, assignment(), endpoint, sequence: 1) }
        XCTAssertEqual(store.sessions.count, 65)
        XCTAssertEqual(store.sidebarSessions, store.sessions)
        XCTAssertNil(arbitration(store))
    }

    private func arbitration(_ store: BrowserMediaSessionStore)
        -> (order: [BrowserMediaSessionSnapshot], nowPlaying: BrowserMediaSessionSnapshot?)?
    {
        BrowserMediaSessionOrdering.arbitration(of: store.sessions)
    }

    private func assignment() -> BrowserTabRuntimeAssignment {
        BrowserTabRuntimeAssignment(tabID: UUID(), spaceID: UUID(), profileID: UUID())
    }

    private func receive(
        _ store: BrowserMediaSessionStore, _ owner: BrowserTabRuntimeAssignment, _ endpoint: Endpoint,
        sequence: UInt64, document: String = "document", playback: BrowserMediaSessionPlaybackState = .playing,
        audible: Bool = true, muted: Bool = false, actions: Set<MediaSessionAction> = [.play, .pause],
        invalidated: Bool = false
    ) {
        store.receive(
            BrowserMediaSessionPageEvent(
                documentIdentifier: document, sequence: sequence, location: "https://example.com/video",
                isInvalidated: invalidated, hasActiveSession: true, title: "Video", artist: nil, album: nil,
                artworkData: nil, playbackState: playback, isAudible: audible, isMuted: muted, availableActions: actions
            ),
            owner: owner, fallbackTitle: "Tab", endpoint: endpoint)
    }

    private final class Endpoint: BrowserMediaSessionCommandEndpoint {
        var actions: [MediaSessionAction] = []

        func performMediaSessionAction(_ action: MediaSessionAction, documentIdentifier: String) {
            actions.append(action)
        }

        func setMediaSessionMuted(_ muted: Bool, documentIdentifier: String) {}
    }
}
