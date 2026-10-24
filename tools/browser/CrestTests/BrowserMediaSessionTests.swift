import Foundation
import XCTest

@testable import Crest

@MainActor
final class BrowserMediaSessionTests: XCTestCase {
    func testMetadataPlaybackAndActionsUpdateOneStableSession() {
        let store = BrowserMediaSessionStore()
        let endpoint = FakeMediaSessionEndpoint()
        let owner = assignment()

        store.receive(
            event(
                document: "document-a",
                sequence: 1,
                title: "First title",
                playback: .paused,
                actions: [.play]
            ),
            owner: owner,
            fallbackTitle: nil,
            endpoint: endpoint
        )
        let ordinal = store.sessions.first?.orderingOrdinal

        store.receive(
            event(
                document: "document-a",
                sequence: 2,
                title: "Second title",
                artist: "Artist",
                playback: .playing,
                audible: false,
                actions: [.pause, .nextTrack]
            ),
            owner: owner,
            fallbackTitle: nil,
            endpoint: endpoint
        )

        XCTAssertEqual(store.sessions.count, 1)
        XCTAssertEqual(store.sessions[0].title, "Second title")
        XCTAssertEqual(store.sessions[0].artist, "Artist")
        XCTAssertEqual(store.sessions[0].playbackState, .playing)
        XCTAssertFalse(
            store.sessions[0].isAudible,
            "Playback truth is independent of audibility."
        )
        XCTAssertEqual(store.sessions[0].availableActions, [.pause, .nextTrack])
        XCTAssertEqual(store.sessions[0].orderingOrdinal, ordinal)
    }

    func testStaleEventsCannotOverwriteOrResurrectRetiredDocuments() {
        let store = BrowserMediaSessionStore()
        let endpoint = FakeMediaSessionEndpoint()
        let owner = assignment()

        store.receive(
            event(document: "old", sequence: 2, title: "Current"),
            owner: owner,
            fallbackTitle: nil,
            endpoint: endpoint
        )
        store.receive(
            event(document: "old", sequence: 1, title: "Stale"),
            owner: owner,
            fallbackTitle: nil,
            endpoint: endpoint
        )
        XCTAssertEqual(store.sessions.first?.title, "Current")

        store.receive(
            event(document: "new", sequence: 1, title: "New document"),
            owner: owner,
            fallbackTitle: nil,
            endpoint: endpoint
        )
        store.receive(
            event(document: "old", sequence: 3, title: "Zombie"),
            owner: owner,
            fallbackTitle: nil,
            endpoint: endpoint
        )

        XCTAssertEqual(store.sessions.map(\.title), ["New document"])
    }

    func testNavigationProcessAndTabCleanupInvalidateOnlyTheOwningEndpoint() {
        let store = BrowserMediaSessionStore()
        let endpointA = FakeMediaSessionEndpoint()
        let endpointB = FakeMediaSessionEndpoint()
        let profileID = UUID()
        let ownerA = assignment(profileID: profileID)
        let ownerB = assignment(profileID: profileID)
        store.receive(
            event(document: "a", sequence: 1, title: "A"),
            owner: ownerA,
            fallbackTitle: nil,
            endpoint: endpointA
        )
        store.receive(
            event(document: "b", sequence: 1, title: "B"),
            owner: ownerB,
            fallbackTitle: nil,
            endpoint: endpointB
        )

        store.invalidate(endpoint: endpointA)
        XCTAssertEqual(store.sessions.map(\.owner), [ownerB])

        store.receive(
            event(document: "a", sequence: 2, title: "Zombie A"),
            owner: ownerA,
            fallbackTitle: nil,
            endpoint: endpointA
        )
        XCTAssertEqual(store.sessions.map(\.owner), [ownerB])

        store.invalidate(owner: ownerB, endpoint: endpointB)
        XCTAssertTrue(store.sessions.isEmpty)
    }

    func testActionsRouteOnlyWhenExposedByTheExactLiveSession() {
        let store = BrowserMediaSessionStore()
        let endpoint = FakeMediaSessionEndpoint()
        let owner = assignment()
        store.receive(
            event(
                document: "document",
                sequence: 1,
                title: "Track",
                playback: .playing,
                actions: [.pause]
            ),
            owner: owner,
            fallbackTitle: nil,
            endpoint: endpoint
        )
        let widgetID = BrowserSidebarWidgetID(
            kindID: .nowPlaying,
            instanceID: store.sessions[0].id.id
        )

        store.perform(.play, on: widgetID)
        store.perform(.pause, on: widgetID)
        store.perform(
            .pause,
            on: BrowserSidebarWidgetID(
                kindID: .nowPlaying,
                instanceID: "another-document"
            )
        )

        XCTAssertEqual(endpoint.actions, [.pause])
        XCTAssertEqual(endpoint.documentIdentifiers, ["document"])
    }

    func testMuteControlRoutesTheInverseStateOnlyForObservedPlayback() async {
        let store = BrowserMediaSessionStore()
        let endpoint = FakeMediaSessionEndpoint()
        let owner = assignment()

        store.receive(
            event(
                document: "document",
                sequence: 1,
                title: "Metadata only",
                playback: .none
            ),
            owner: owner,
            fallbackTitle: nil,
            endpoint: endpoint
        )
        let widgetID = BrowserSidebarWidgetID(
            kindID: .nowPlaying,
            instanceID: store.sessions[0].id.id
        )
        store.perform(.toggleMute, on: widgetID)
        XCTAssertTrue(
            endpoint.mutedRequests.isEmpty,
            "A page that advertises metadata without playback has nothing to mute."
        )

        store.receive(
            event(
                document: "document",
                sequence: 2,
                title: "Playing",
                playback: .playing,
                actions: [.pause]
            ),
            owner: owner,
            fallbackTitle: nil,
            endpoint: endpoint
        )
        var iterator = store.events().makeAsyncIterator()
        let published = await iterator.next() ?? []
        XCTAssertEqual(published.count, 1)
        XCTAssertTrue(
            published[0].availableActions.contains(.toggleMute),
            "Observed playback publishes the widget's volume control."
        )
        XCTAssertFalse(store.sessions[0].isMuted)

        store.perform(.toggleMute, on: widgetID)
        XCTAssertEqual(
            endpoint.mutedRequests,
            [true],
            "Toggling an unmuted session asks the page to mute."
        )

        store.receive(
            event(
                document: "document",
                sequence: 3,
                title: "Playing",
                playback: .playing,
                muted: true,
                actions: [.pause]
            ),
            owner: owner,
            fallbackTitle: nil,
            endpoint: endpoint
        )
        XCTAssertTrue(store.sessions[0].isMuted)
        store.perform(.toggleMute, on: widgetID)
        XCTAssertEqual(endpoint.mutedRequests, [true, false])
    }

    func testDismissingHidesTheCardUntilTheTabStartsPlayingAgain() async {
        let store = BrowserMediaSessionStore()
        let endpoint = FakeMediaSessionEndpoint()
        let owner = assignment()
        var iterator = store.events().makeAsyncIterator()
        _ = await iterator.next()

        store.receive(
            event(
                document: "document",
                sequence: 1,
                title: "Track",
                playback: .paused,
                actions: [.play]
            ),
            owner: owner,
            fallbackTitle: nil,
            endpoint: endpoint
        )
        let widgetID = BrowserSidebarWidgetID(
            kindID: .nowPlaying,
            instanceID: store.sessions[0].id.id
        )
        var published = await iterator.next() ?? []
        XCTAssertEqual(published.count, 1)
        XCTAssertTrue(
            published[0].availableActions.contains(.dismissMediaSession),
            "Every now-playing card can be hidden."
        )

        store.perform(.dismissMediaSession, on: widgetID)
        published = await iterator.next() ?? []
        XCTAssertTrue(published.isEmpty, "Dismissing withholds the card.")
        XCTAssertEqual(
            store.sessions.count,
            1,
            "The session itself keeps running; only its card is withheld."
        )

        store.receive(
            event(
                document: "document",
                sequence: 2,
                title: "Track",
                playback: .paused,
                actions: [.play]
            ),
            owner: owner,
            fallbackTitle: nil,
            endpoint: endpoint
        )
        XCTAssertEqual(
            store.sessions[0].title,
            "Track",
            "Ordinary updates to a hidden session do not bring its card back."
        )

        store.receive(
            event(
                document: "document",
                sequence: 3,
                title: "Track",
                playback: .playing,
                actions: [.pause]
            ),
            owner: owner,
            fallbackTitle: nil,
            endpoint: endpoint
        )
        published = await iterator.next() ?? []
        XCTAssertEqual(
            published.count,
            1,
            "Playing again from a non-playing state brings the card back."
        )
    }

    func testDismissalRecordsAreDroppedWhenTheSessionGoesAway() async {
        let store = BrowserMediaSessionStore()
        let endpoint = FakeMediaSessionEndpoint()
        let owner = assignment()

        store.receive(
            event(document: "document", sequence: 1, title: "Track", playback: .playing),
            owner: owner,
            fallbackTitle: nil,
            endpoint: endpoint
        )
        store.perform(
            .dismissMediaSession,
            on: BrowserSidebarWidgetID(
                kindID: .nowPlaying,
                instanceID: store.sessions[0].id.id
            )
        )
        XCTAssertTrue(store.widgetInstances.isEmpty)

        store.invalidate(endpoint: endpoint)
        XCTAssertTrue(store.sessions.isEmpty)

        // The same tab and document identifier reappearing is a new session, and
        // a stale dismissal must not hide it.
        let revived = assignment(profileID: owner.profileID)
        store.receive(
            event(document: "document", sequence: 1, title: "Track", playback: .playing),
            owner: revived,
            fallbackTitle: nil,
            endpoint: endpoint
        )
        XCTAssertEqual(
            store.widgetInstances.count,
            1,
            "Dismissal records do not outlive the session they belong to."
        )
    }

    func testStaleEventRetentionIsBounded() {
        let store = BrowserMediaSessionStore()
        let endpoint = FakeMediaSessionEndpoint()
        let owner = assignment()
        for index in 0..<600 {
            let event = BrowserMediaSessionPageEvent(
                documentIdentifier: "retired-\(index)",
                sequence: 1,
                location: "https://fixture.invalid/media",
                isInvalidated: true,
                hasActiveSession: false,
                title: nil,
                artist: nil,
                album: nil,
                artworkData: nil,
                playbackState: .none,
                isAudible: false,
                isMuted: false,
                availableActions: []
            )
            store.receive(
                event,
                owner: owner,
                fallbackTitle: nil,
                endpoint: endpoint
            )
        }

        XCTAssertEqual(store.retainedEventIdentityCount, 512)
        XCTAssertTrue(store.sessions.isEmpty)
    }

    func testDecoderBoundsTextArtworkAndRecognizedActions() throws {
        let imageData = Data(repeating: 7, count: 64)
        let decoded = try XCTUnwrap(
            BrowserMediaSessionPageEventDecoder.decode([
                "version": 1,
                "documentIdentifier": "document",
                "sequence": 1,
                "location": "https://fixture.invalid/media",
                "active": true,
                "title": "Track",
                "artist": String(repeating: "a", count: 513),
                "artworkDataURL": "data:image/png;base64,\(imageData.base64EncodedString())",
                "playbackState": "paused",
                "audible": false,
                "muted": true,
                "actions": ["play", "seekto", "nexttrack"],
            ])
        )

        XCTAssertEqual(decoded.artworkData, imageData)
        XCTAssertNil(decoded.artist)
        XCTAssertEqual(decoded.availableActions, [.play, .nextTrack])
        XCTAssertTrue(decoded.isMuted)
        XCTAssertFalse(
            try XCTUnwrap(
                BrowserMediaSessionPageEventDecoder.decode([
                    "version": 1,
                    "documentIdentifier": "document",
                    "sequence": 1,
                    "location": "https://fixture.invalid/media",
                    "active": true,
                    "playbackState": "paused",
                ])
            ).isMuted,
            "A payload without a mute flag never reports a muted page."
        )

        let oversized = Data(
            repeating: 1,
            count: BrowserMediaSessionPageEventDecoder.maximumArtworkBytes + 1
        )
        XCTAssertNil(
            BrowserMediaSessionPageEventDecoder.artworkData(
                fromDataURL: "data:image/png;base64,\(oversized.base64EncodedString())"
            )
        )
        XCTAssertNil(
            BrowserMediaSessionPageEventDecoder.artworkData(
                fromDataURL: "https://private.example/artwork.png"
            ),
            "Crest must not refetch page artwork across WebKit security boundaries."
        )
    }

    private func assignment(profileID: UUID = UUID()) -> BrowserTabRuntimeAssignment {
        BrowserTabRuntimeAssignment(
            tabID: UUID(),
            spaceID: UUID(),
            profileID: profileID
        )
    }

    private func event(
        document: String,
        sequence: UInt64,
        title: String?,
        artist: String? = nil,
        playback: BrowserMediaSessionPlaybackState = .paused,
        audible: Bool = false,
        muted: Bool = false,
        actions: Set<MediaSessionAction> = [.play, .pause]
    ) -> BrowserMediaSessionPageEvent {
        BrowserMediaSessionPageEvent(
            documentIdentifier: document,
            sequence: sequence,
            location: "https://fixture.invalid/media",
            isInvalidated: false,
            hasActiveSession: true,
            title: title,
            artist: artist,
            album: nil,
            artworkData: nil,
            playbackState: playback,
            isAudible: audible,
            isMuted: muted,
            availableActions: actions
        )
    }
}

@MainActor
private final class FakeMediaSessionEndpoint: BrowserMediaSessionCommandEndpoint {
    private(set) var actions: [MediaSessionAction] = []
    private(set) var documentIdentifiers: [String] = []
    private(set) var mutedRequests: [Bool] = []

    func performMediaSessionAction(
        _ action: MediaSessionAction,
        documentIdentifier: String
    ) {
        actions.append(action)
        documentIdentifiers.append(documentIdentifier)
    }

    func setMediaSessionMuted(
        _ muted: Bool,
        documentIdentifier: String
    ) {
        mutedRequests.append(muted)
        documentIdentifiers.append(documentIdentifier)
    }
}
