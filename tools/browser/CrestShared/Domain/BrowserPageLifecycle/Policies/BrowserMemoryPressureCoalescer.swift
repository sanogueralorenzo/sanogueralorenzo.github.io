import Foundation

/// Collapses memory-pressure signals that describe one squeeze.
///
/// iOS can report one squeeze through both the kernel pressure source and UIKit's
/// memory warning. An escalation is never collapsed because critical pressure may
/// release active transient surfaces that a warning deliberately preserved.
struct BrowserMemoryPressureCoalescer {
    /// How long one signal speaks for. Long enough to cover a source and a
    /// notification arriving together, short enough that sustained pressure can
    /// be handled again.
    static let defaultWindow: TimeInterval = 1

    private let window: TimeInterval
    private var handled: (level: MemoryPressureLevel, time: Date)?

    init(window: TimeInterval = BrowserMemoryPressureCoalescer.defaultWindow) {
        precondition(window >= 0)
        self.window = window
    }

    /// Whether `level` at `time` is pressure worth acting on, recording it when it
    /// is. A clock that jumped either way is treated as a new window rather than
    /// as a reason to skip handling the signal.
    mutating func shouldHandle(
        _ level: MemoryPressureLevel,
        at time: Date
    ) -> Bool {
        if let handled,
            abs(time.timeIntervalSince(handled.time)) < window,
            level <= handled.level
        {
            return false
        }
        handled = (level, time)
        return true
    }
}
