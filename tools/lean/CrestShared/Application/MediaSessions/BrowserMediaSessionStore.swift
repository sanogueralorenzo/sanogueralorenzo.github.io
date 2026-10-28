import Foundation
import Observation

@MainActor
protocol BrowserMediaSessionCommandEndpoint: AnyObject {
    func performMediaSessionAction(
        _ action: MediaSessionAction,
        documentIdentifier: String
    )

    func setMediaSessionMuted(
        _ muted: Bool,
        documentIdentifier: String
    )
}

struct BrowserMediaSessionPageEvent: Equatable, Sendable {
    let documentIdentifier: String
    let sequence: UInt64
    let location: String
    let isInvalidated: Bool
    let hasActiveSession: Bool
    let title: String?
    let artist: String?
    let album: String?
    let artworkData: Data?
    let playbackState: BrowserMediaSessionPlaybackState
    let isAudible: Bool
    let isMuted: Bool
    let availableActions: Set<MediaSessionAction>
}

enum BrowserMediaSessionPageEventDecoder {
    static let maximumTextLength = 512
    static let maximumDocumentIdentifierLength = 128
    static let maximumLocationLength = 4_096
    /// Preserve standards-provided artwork bytes whenever they fit the bounded
    /// native payload. Only a larger page resource is rasterized by the bridge.
    static let maximumArtworkInputBytes = 8 * 1_024 * 1_024
    static let maximumArtworkBytes = 4 * 1_024 * 1_024
    static let maximumArtworkDataURLCharacters = 5_600_128
    static let maximumArtworkSourceCharacters = 11_200_256
    static let maximumOversizeArtworkPixelSize = 2_048

    static func decode(_ body: Any) -> BrowserMediaSessionPageEvent? {
        guard let body = body as? [String: Any],
            (body["version"] as? Int) == 1,
            let documentIdentifier = boundedString(
                body["documentIdentifier"],
                maximum: maximumDocumentIdentifierLength
            ),
            let sequenceNumber = body["sequence"] as? NSNumber,
            let location = boundedString(
                body["location"],
                maximum: maximumLocationLength
            )
        else { return nil }

        let actions = Set(
            (body["actions"] as? [String] ?? []).compactMap(
                MediaSessionAction.init(pageName:)
            )
        )
        let playbackState =
            BrowserMediaSessionPlaybackState(
                rawValue: body["playbackState"] as? String ?? ""
            ) ?? .none
        return BrowserMediaSessionPageEvent(
            documentIdentifier: documentIdentifier,
            sequence: sequenceNumber.uint64Value,
            location: location,
            isInvalidated: body["invalidated"] as? Bool == true,
            hasActiveSession: body["active"] as? Bool == true,
            title: boundedString(body["title"], maximum: maximumTextLength),
            artist: boundedString(body["artist"], maximum: maximumTextLength),
            album: boundedString(body["album"], maximum: maximumTextLength),
            artworkData: artworkData(
                fromDataURL: body["artworkDataURL"] as? String
            ),
            playbackState: playbackState,
            isAudible: body["audible"] as? Bool == true,
            isMuted: body["muted"] as? Bool == true,
            availableActions: actions
        )
    }

    static func artworkData(fromDataURL dataURL: String?) -> Data? {
        guard let dataURL,
            dataURL.count <= maximumArtworkDataURLCharacters,
            dataURL.hasPrefix("data:image/png;base64,")
                || dataURL.hasPrefix("data:image/jpeg;base64,")
                || dataURL.hasPrefix("data:image/webp;base64,")
        else { return nil }
        guard let comma = dataURL.firstIndex(of: ",") else { return nil }
        let encoded = String(dataURL[dataURL.index(after: comma)...])
        guard let data = Data(base64Encoded: encoded),
            data.count <= maximumArtworkBytes
        else { return nil }
        return data
    }

    private static func boundedString(
        _ value: Any?,
        maximum: Int
    ) -> String? {
        guard let value = value as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= maximum else { return nil }
        return trimmed
    }
}

@Observable
@MainActor
final class BrowserMediaSessionStore {
    private final class WeakEndpoint {
        weak var value: (any BrowserMediaSessionCommandEndpoint)?

        init(_ value: any BrowserMediaSessionCommandEndpoint) {
            self.value = value
        }
    }

    /// Published sessions in first-published display order.
    private(set) var sessions: [BrowserMediaSessionSnapshot] = []

    @ObservationIgnored private var snapshotsByID: [BrowserMediaSessionID: BrowserMediaSessionSnapshot] = [:]
    @ObservationIgnored private var endpointsByID: [BrowserMediaSessionID: WeakEndpoint] = [:]
    @ObservationIgnored private var ownersByID: [BrowserMediaSessionID: BrowserTabRuntimeAssignment] = [:]
    @ObservationIgnored private var lastSequenceByID: [BrowserMediaSessionID: UInt64] = [:]
    @ObservationIgnored private var sequenceOrder: [BrowserMediaSessionID] = []
    @ObservationIgnored private var retiredIDs: Set<BrowserMediaSessionID> = []
    @ObservationIgnored private var ordinalByID: [BrowserMediaSessionID: UInt64] = [:]
    @ObservationIgnored private var nextOrdinal: UInt64 = 1
    @ObservationIgnored
    private var sessionSubscribers: [UUID: AsyncStream<[BrowserMediaSessionSnapshot]>.Continuation] = [:]
    /// Sessions the reader has hidden. The session itself keeps running and keeps
    /// reporting; only its card is withheld until the tab plays again.
    @ObservationIgnored private var dismissedIDs: Set<BrowserMediaSessionID> = []
    private(set) var sidebarSessions: [BrowserMediaSessionSnapshot] = []

    /// Accept sequenced reports only from live documents. Muted cards remain
    /// controllable; starting playback restores a card the person dismissed.
    func receive(
        _ event: BrowserMediaSessionPageEvent,
        owner: BrowserTabRuntimeAssignment,
        fallbackTitle: String?,
        endpoint: any BrowserMediaSessionCommandEndpoint
    ) {
        let id = BrowserMediaSessionID(tabID: owner.tabID, documentIdentifier: event.documentIdentifier)
        guard !retiredIDs.contains(id), event.sequence > (lastSequenceByID[id] ?? 0) else { return }
        let retained = lastSequenceByID.count + (lastSequenceByID[id] == nil ? 1 : 0)
        recordSequence(event.sequence, for: id, evictingOldest: max(0, retained - 512))
        endpointsByID[id] = WeakEndpoint(endpoint)
        ownersByID[id] = owner
        if event.isInvalidated {
            retire(id)
        } else if !event.hasActiveSession
            || !(event.availableActions.contains(.play) || event.availableActions.contains(.pause)
                || (event.isMuted && snapshotsByID[id] != nil))
        {
            snapshotsByID[id] = nil
        } else {
            publish(event, id: id, owner: owner, fallbackTitle: fallbackTitle)
        }
        publishIfChanged()
    }

    private func publish(
        _ event: BrowserMediaSessionPageEvent, id: BrowserMediaSessionID,
        owner: BrowserTabRuntimeAssignment, fallbackTitle: String?
    ) {
        let ordinal = ordinalByID[id] ?? nextOrdinal
        if ordinalByID[id] == nil { nextOrdinal &+= 1 }
        if snapshotsByID[id]?.playbackState != .playing, event.playbackState == .playing {
            dismissedIDs.remove(id)
        }
        // A new document supersedes all earlier media documents in this tab.
        let superseded = ownersByID.keys.filter { $0.tabID == owner.tabID && $0 != id }
        for previousID in superseded { retire(previousID) }
        ordinalByID[id] = ordinal
        snapshotsByID[id] = BrowserMediaSessionSnapshot(
            id: id, owner: owner, ownerTitle: Self.boundedFallbackTitle(fallbackTitle),
            title: event.title, artist: event.artist, album: event.album, artworkData: event.artworkData,
            playbackState: event.playbackState, isAudible: event.isAudible, isMuted: event.isMuted,
            availableActions: event.availableActions, orderingOrdinal: ordinal
        )
    }

    func invalidate(
        owner: BrowserTabRuntimeAssignment,
        endpoint: any BrowserMediaSessionCommandEndpoint
    ) {
        let endpointID = ObjectIdentifier(endpoint)
        let matching = ownersByID.keys.filter { id in
            guard ownersByID[id] == owner,
                let existing = endpointsByID[id]?.value
            else { return false }
            return ObjectIdentifier(existing) == endpointID
        }
        guard !matching.isEmpty else { return }
        for id in matching { retire(id) }
        publishIfChanged()
    }

    func invalidate(endpoint: any BrowserMediaSessionCommandEndpoint) {
        let endpointID = ObjectIdentifier(endpoint)
        let matching: [BrowserMediaSessionID] = endpointsByID.compactMap {
            id,
            weakEndpoint -> BrowserMediaSessionID? in
            guard let existing = weakEndpoint.value,
                ObjectIdentifier(existing) == endpointID
            else { return nil }
            return id
        }
        guard !matching.isEmpty else { return }
        for id in matching { retire(id) }
        publishIfChanged()
    }

    /// The authoritative page-session stream. Platform adapters consume this
    /// rather than observing sidebar visibility, because hiding a card must not
    /// erase the page's actual media session.
    func sessionEvents() -> AsyncStream<[BrowserMediaSessionSnapshot]> {
        let subscriberID = UUID()
        let (stream, continuation) = AsyncStream<[BrowserMediaSessionSnapshot]>.makeStream(
            bufferingPolicy: .bufferingNewest(1)
        )
        sessionSubscribers[subscriberID] = continuation
        continuation.onTermination = { @Sendable [weak self] _ in
            Task { @MainActor [weak self] in
                self?.sessionSubscribers.removeValue(forKey: subscriberID)
            }
        }
        continuation.yield(sessions)
        return stream
    }

    /// The session the tab's page publishes, or nil while it publishes none.
    /// The store keeps one session per tab, and hiding its card does not hide
    /// it. Reading it observes the published sessions.
    func session(of owner: BrowserTabRuntimeAssignment) -> BrowserMediaSessionSnapshot? {
        sessions.first { $0.owner == owner }
    }

    /// Mutes or unmutes the tab's session, where Crest has observed its
    /// playback.
    func setMuted(_ muted: Bool, of owner: BrowserTabRuntimeAssignment) {
        guard let session = session(of: owner) else { return }
        setMuted(muted, session)
    }

    /// Asks the page to mute or unmute the session, where Crest has observed
    /// its playback.
    private func setMuted(_ muted: Bool, _ snapshot: BrowserMediaSessionSnapshot) {
        guard Self.exposesMuteControl(snapshot),
            let endpoint = endpointsByID[snapshot.id]?.value
        else { return }
        endpoint.setMediaSessionMuted(muted, documentIdentifier: snapshot.id.documentIdentifier)
    }

    /// Muting addresses page media elements directly, so the control belongs to
    /// any session whose playback Crest has actually observed — not to the set of
    /// Media Session action handlers the page happens to register.
    private static func exposesMuteControl(
        _ snapshot: BrowserMediaSessionSnapshot
    ) -> Bool {
        snapshot.playbackState != .none
    }

    private func retire(_ id: BrowserMediaSessionID) {
        snapshotsByID[id] = nil
        endpointsByID[id] = nil
        ownersByID[id] = nil
        ordinalByID[id] = nil
        dismissedIDs.remove(id)
        retiredIDs.insert(id)
    }

    private func recordSequence(
        _ sequence: UInt64,
        for id: BrowserMediaSessionID,
        evictingOldest requested: Int
    ) {
        if lastSequenceByID[id] == nil { sequenceOrder.append(id) }
        lastSequenceByID[id] = sequence
        let overflow = min(requested, max(sequenceOrder.count - 1, 0))
        guard overflow > 0 else { return }
        for expiredID in sequenceOrder.prefix(overflow) {
            lastSequenceByID[expiredID] = nil
            retiredIDs.remove(expiredID)
            if snapshotsByID[expiredID] == nil {
                endpointsByID[expiredID] = nil
                ownersByID[expiredID] = nil
                ordinalByID[expiredID] = nil
                dismissedIDs.remove(expiredID)
            }
        }
        sequenceOrder.removeFirst(overflow)
    }

    /// At the arbitration limit, surviving sessions keep their places and new
    /// ones follow in the order they arrived.
    private func publishIfChanged() {
        let current = Array(snapshotsByID.values)
        let next =
            BrowserMediaSessionOrdering.arbitration(of: current)?.order
            ?? {
                let placed = sessions.compactMap { snapshotsByID[$0.id] }
                let placedIDs = Set(placed.map(\.id))
                let arrivals = current.filter { !placedIDs.contains($0.id) }
                    .sorted { $0.orderingOrdinal < $1.orderingOrdinal }
                return placed + arrivals
            }()
        if next != sessions {
            sessions = next
            for continuation in sessionSubscribers.values {
                continuation.yield(next)
            }
        }
        let visible = sessions.filter { !dismissedIDs.contains($0.id) }
        if visible != sidebarSessions { sidebarSessions = visible }
    }

    private static func boundedFallbackTitle(_ title: String?) -> String? {
        guard let title else { return nil }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
            trimmed.count <= BrowserMediaSessionPageEventDecoder.maximumTextLength
        else { return nil }
        return trimmed
    }
}

extension BrowserMediaSessionStore {
    func dismissCard(of id: BrowserMediaSessionID) {
        // Hiding a card is Crest's own state, so it does not need the page to
        // still be reachable.
        guard snapshotsByID[id] != nil, dismissedIDs.insert(id).inserted else { return }
        publishIfChanged()
    }

    func toggleMute(of id: BrowserMediaSessionID) {
        guard let session = snapshotsByID[id] else { return }
        setMuted(!session.isMuted, session)
    }

    func perform(_ action: MediaSessionAction, on id: BrowserMediaSessionID) {
        guard let session = snapshotsByID[id], let endpoint = endpointsByID[session.id]?.value,
            session.availableActions.contains(action)
        else { return }
        endpoint.performMediaSessionAction(
            action,
            documentIdentifier: session.id.documentIdentifier
        )
    }
}
