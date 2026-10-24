import AppKit
import ImageIO
@preconcurrency import MediaPlayer

@MainActor
protocol BrowserSystemNowPlayingDriving: AnyObject {
    func setCommandHandler(
        _ handler: ((MediaSessionAction) -> Bool)?
    )
    func publish(_ session: BrowserMediaSessionSnapshot?)
}

/// Projects the shared page-session lifecycle into macOS Now Playing without
/// creating a second media-session store. Its single task is explicitly owned,
/// deduplicated, cancellable, and backed by the store's newest-only event stream.
@MainActor
final class BrowserSystemNowPlayingCoordinator {
    private let store: BrowserMediaSessionStore
    private let driver: any BrowserSystemNowPlayingDriving
    private var selectedSession: BrowserMediaSessionSnapshot?
    private var task: Task<Void, Never>?

    init(
        store: BrowserMediaSessionStore,
        driver: any BrowserSystemNowPlayingDriving =
            BrowserMediaPlayerNowPlayingDriver()
    ) {
        self.store = store
        self.driver = driver
    }

    func start() {
        guard task == nil else { return }
        driver.setCommandHandler { [weak self] action in
            self?.perform(action) == true
        }
        task = Task { @MainActor [weak self] in
            guard let self else { return }
            for await sessions in store.sessionEvents() {
                guard !Task.isCancelled else { break }
                publishSelection(from: sessions)
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        selectedSession = nil
        driver.setCommandHandler(nil)
        driver.publish(nil)
    }

    /// macOS represents one browser session at a time; which one is the core's
    /// `media.arbitrate` rule. Multiple page sessions stay authoritative in the
    /// shared store and sidebar. Without an answer the current owner keeps Now
    /// Playing while it is still playing or paused, and nothing takes over.
    private func publishSelection(
        from sessions: [BrowserMediaSessionSnapshot]
    ) {
        let next: BrowserMediaSessionSnapshot?
        if let arbitration = MediaSessionOrder.arbitration(of: sessions) {
            next = arbitration.nowPlaying
        } else {
            next = selectedSession.flatMap { selected in
                sessions.first { $0.id == selected.id && $0.playbackState != .none }
            }
        }
        guard next != selectedSession else { return }
        selectedSession = next
        driver.publish(next)
    }

    private func perform(_ action: MediaSessionAction) -> Bool {
        guard let selectedSession,
            selectedSession.availableActions.contains(action)
        else { return false }
        let widgetID = BrowserSidebarWidgetID(
            kindID: .nowPlaying,
            instanceID: selectedSession.id.id
        )
        store.perform(.mediaSession(action), on: widgetID)
        return true
    }
}

/// Public MediaPlayer-framework adapter for macOS Control Center, media keys,
/// and accessories. Page artwork has already crossed the bounded page bridge;
/// it is downsampled once more at the framework boundary before publication.
@MainActor
final class BrowserMediaPlayerNowPlayingDriver: NSObject,
    BrowserSystemNowPlayingDriving
{
    /// The largest artwork the system's Now Playing surface is handed.
    private nonisolated static let maximumArtworkPixelSize = 1_024

    private let infoCenter: MPNowPlayingInfoCenter
    private let commandCenter: MPRemoteCommandCenter
    private var commandHandler: ((MediaSessionAction) -> Bool)?
    private var commandTargets: [(command: MPRemoteCommand, target: Any)] = []

    init(
        infoCenter: MPNowPlayingInfoCenter = .default(),
        commandCenter: MPRemoteCommandCenter = .shared()
    ) {
        self.infoCenter = infoCenter
        self.commandCenter = commandCenter
        super.init()
        install(commandCenter.playCommand, action: .play)
        install(commandCenter.pauseCommand, action: .pause)
        install(commandCenter.previousTrackCommand, action: .previousTrack)
        install(commandCenter.nextTrackCommand, action: .nextTrack)
        setEnabledActions([])
    }

    isolated deinit {
        for entry in commandTargets {
            entry.command.removeTarget(entry.target)
        }
    }

    func setCommandHandler(
        _ handler: ((MediaSessionAction) -> Bool)?
    ) {
        commandHandler = handler
    }

    func publish(_ session: BrowserMediaSessionSnapshot?) {
        guard let session else {
            infoCenter.nowPlayingInfo = nil
            infoCenter.playbackState = .stopped
            setEnabledActions([])
            return
        }

        var info: [String: Any] = [
            MPMediaItemPropertyTitle: session.displayTitle,
            MPNowPlayingInfoPropertyExternalContentIdentifier: session.id.id,
            MPNowPlayingInfoPropertyExcludeFromSuggestions: true,
            MPNowPlayingInfoPropertyPlaybackRate:
                session.playbackState == .playing ? 1.0 : 0.0,
        ]
        if let artist = session.artist { info[MPMediaItemPropertyArtist] = artist }
        if let album = session.album { info[MPMediaItemPropertyAlbumTitle] = album }
        if let artworkData = session.artworkData,
            let artwork = Self.artwork(from: artworkData)
        {
            info[MPMediaItemPropertyArtwork] = artwork
        }
        infoCenter.nowPlayingInfo = info
        infoCenter.playbackState =
            session.playbackState == .playing ? .playing : .paused
        setEnabledActions(session.availableActions)
    }

    private func install(
        _ command: MPRemoteCommand,
        action: MediaSessionAction
    ) {
        let target = command.addTarget { [weak self] _ in
            guard self?.commandHandler?(action) == true else {
                return .commandFailed
            }
            return .success
        }
        commandTargets.append((command, target))
    }

    private func setEnabledActions(
        _ actions: Set<MediaSessionAction>
    ) {
        commandCenter.playCommand.isEnabled = actions.contains(.play)
        commandCenter.pauseCommand.isEnabled = actions.contains(.pause)
        commandCenter.previousTrackCommand.isEnabled = actions.contains(.previousTrack)
        commandCenter.nextTrackCommand.isEnabled = actions.contains(.nextTrack)
    }

    nonisolated static func artwork(from data: Data) -> MPMediaItemArtwork? {
        guard
            let source = CGImageSourceCreateWithData(
                data as CFData,
                [kCGImageSourceShouldCache: false] as CFDictionary
            ),
            let image = CGImageSourceCreateThumbnailAtIndex(
                source,
                0,
                [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize:
                        maximumArtworkPixelSize,
                    kCGImageSourceShouldCacheImmediately: true,
                ] as CFDictionary
            )
        else { return nil }
        let size = NSSize(width: image.width, height: image.height)
        return MPMediaItemArtwork(boundsSize: size) { requestedSize in
            // MediaPlayer supplies bounding dimensions for its current surface.
            // Return the largest natural-aspect image inside those bounds so
            // video stays wide, book art stays tall, and album art stays square.
            let bounds = CGSize(
                width: max(requestedSize.width, 1),
                height: max(requestedSize.height, 1)
            )
            let scale = min(
                bounds.width / CGFloat(image.width),
                bounds.height / CGFloat(image.height)
            )
            let renderedSize = NSSize(
                width: max((CGFloat(image.width) * scale).rounded(), 1),
                height: max((CGFloat(image.height) * scale).rounded(), 1)
            )
            return NSImage(cgImage: image, size: renderedSize)
        }
    }
}
