import AppKit
@preconcurrency import MediaPlayer

@MainActor final class BrowserSystemMedia {
    weak var owner: BrowserSessionOwner?
    private var selected: UUID?
    var currentPage: BrowserPage? { selected.flatMap { owner?.pages[$0] } }
    private var targets: [(MPRemoteCommand, Any)] = []
    init(owner: BrowserSessionOwner) {
        self.owner = owner
        let center = MPRemoteCommandCenter.shared()
        for (command, action) in [
            (center.playCommand, "play"), (center.pauseCommand, "pause"),
            (center.togglePlayPauseCommand, "toggle"), (center.nextTrackCommand, "nexttrack"),
            (center.previousTrackCommand, "previoustrack"), (center.skipForwardCommand, "seekforward"),
            (center.skipBackwardCommand, "seekbackward"),
        ] {
            let target = command.addTarget { [weak self] _ in
                Task { @MainActor in self?.perform(action) }
                return .success
            }
            targets.append((command, target))
        }
        let target = center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            let time = event.positionTime
            Task { @MainActor in self?.perform("seekto", time: time) }
            return .success
        }
        targets.append((center.changePlaybackPositionCommand, target))
    }

    func refresh() {
        guard let owner else { return }
        let playing = owner.pages.values.filter { $0.isPlaying }.sorted { $0.lastSelected > $1.lastSelected }
        let page = playing.first ?? selected.flatMap { owner.pages[$0] }
        selected = page?.id
        let center = MPNowPlayingInfoCenter.default()
        guard let page else {
            center.nowPlayingInfo = nil
            center.playbackState = .stopped
            return
        }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: page.mediaTitle.isEmpty ? page.title : page.mediaTitle,
            MPMediaItemPropertyArtist: page.mediaArtist, MPMediaItemPropertyPlaybackDuration: page.mediaDuration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: page.mediaElapsed,
            MPNowPlayingInfoPropertyPlaybackRate: page.isPlaying ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyExternalContentIdentifier: page.id.uuidString,
        ]
        if let data = page.favicon, let image = NSImage(data: data) {
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        }
        center.nowPlayingInfo = info
        center.playbackState = page.isPlaying ? .playing : .paused
    }

    func perform(_ action: String, time: Double? = nil) {
        guard let selected, let page = owner?.pages[selected] else { return }
        page.performMediaAction(action == "toggle" ? (page.isPlaying ? "pause" : "play") : action, time: time)
    }

    func stop() {
        for (command, target) in targets { command.removeTarget(target) }
        targets.removeAll()
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }
}
