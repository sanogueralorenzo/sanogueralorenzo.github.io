import Dispatch
import Foundation

/// The app's one memory pressure source. Each squeeze first releases what
/// every page owner keeps itself, then tells the core once, which unloads the
/// tab pages off screen longest, as many as the device gives back at that
/// level, from what each page last told it about its media.
@MainActor
final class BrowserMemoryPressureMonitor {
    // MARK: - Variables

    private weak var core: CrestCore?
    /// Every page owner alive now, in every window and browsing mode.
    private let owners: @MainActor () -> [any BrowserPageOwner]
    private var source: (any DispatchSourceMemoryPressure)?
    private var coalescer = BrowserMemoryPressureCoalescer()

    // MARK: - Initializers

    init(core: CrestCore, owners: @escaping @MainActor () -> [any BrowserPageOwner]) {
        self.core = core
        self.owners = owners
    }

    // MARK: - Actions - Monitoring

    /// Starts following the system's memory pressure.
    func start() {
        guard source == nil else { return }
        let source = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .main)
        source.setEventHandler { [weak self] in
            // `dispatch_source_get_data` is only defined while this handler is
            // running: read after a hop it answers zero, and critical pressure
            // would forever look like a warning. The source runs on the main
            // queue, so the event is captured and handled without one.
            MainActor.assumeIsolated {
                guard let self, let source = self.source else { return }
                self.handle(source.data)
            }
        }
        self.source = source
        source.resume()
    }

    /// Handles one kernel pressure event, captured inside the source's own
    /// handler.
    func handle(_ event: DispatchSource.MemoryPressureEvent, at time: Date = .now) {
        relieve(event.contains(.critical) ? MemoryPressureLevel.critical : .warning, at: time)
    }

    /// Relieves one squeeze at `level`, once however many signals it sends:
    /// the kernel's source and, on iOS, the memory warning every scene hears.
    func relieve(_ level: MemoryPressureLevel, at time: Date = .now) {
        guard coalescer.shouldHandle(level, at: time) else { return }
        for owner in owners() { owner.relieveMemoryPressure(level) }
        let changes = (try? core?.send(ReportMemoryPressure(level: level))) ?? []
        let unloaded = changes.compactMap { change -> UUID? in
            guard case .pageUnloaded(let unloaded) = change else { return nil }
            return unloaded.tabID
        }
        DiagnosticLog.pages.notice(
            "Memory pressure \(level.name) unloads the pages of tabs \(unloaded.map(\.uuidString))")
    }

    deinit {
        source?.cancel()
    }
}
