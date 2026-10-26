import Foundation

/// The sound one page plays, measured band by band by its engine while
/// anything watches it. The engine measures only while a watcher is there, so
/// a tab whose bars are off screen costs nothing.
@MainActor
final class BrowserAudioSpectrumFeed {
    // MARK: - Variables

    /// Asks the engine to start or stop measuring.
    private let observe: @MainActor (Bool) -> Void
    private var watchers: [UUID: @MainActor (Data) -> Void] = [:]

    // MARK: - Initializers

    init(observe: @escaping @MainActor (Bool) -> Void) {
        self.observe = observe
    }

    // MARK: - Actions - Watching

    /// Hands `watcher` each measure from now on, one level from 0 to 255 per
    /// band, lowest first, and answers the watch to end later. The first
    /// watcher starts the engine measuring.
    func watch(_ watcher: @escaping @MainActor (Data) -> Void) -> UUID {
        let watch = UUID()
        watchers[watch] = watcher
        if watchers.count == 1 { observe(true) }
        return watch
    }

    /// Ends the watch `watch`. The last one to end stops the engine measuring.
    func unwatch(_ watch: UUID) {
        guard watchers.removeValue(forKey: watch) != nil, watchers.isEmpty else { return }
        observe(false)
    }

    // MARK: - Actions - Measures

    /// Hands a measure the engine made to every watcher.
    func receive(_ bands: Data) {
        for watcher in watchers.values { watcher(bands) }
    }
}
