import AppKit
import WebKit

/// The desktop embedder preference used by WebKit's MiniBrowser. Resolve SPI
/// exactly as the inspector does; unavailable SPI leaves native PiP disabled.
@MainActor
enum BrowserDesktopPictureInPictureAccess {
    @discardableResult
    static func enable(in preferences: NSObject) -> Bool {
        let selector = NSSelectorFromString("_setAllowsPictureInPictureMediaPlayback:")
        guard preferences.responds(to: selector) else { return false }
        typealias Setter = @convention(c) (AnyObject, Selector, Bool) -> Void
        let setter = unsafeBitCast(preferences.method(for: selector), to: Setter.self)
        setter(preferences, selector, true)
        return true
    }

    /// Window metadata is public and does not capture screen contents or need
    /// Screen Recording permission. A running PIPAgent alone is not an active
    /// session: the agent stays alive after its last window closes.
    static func isSystemOccupied() -> Bool {
        guard
            let windows = CGWindowListCopyWindowInfo(
                [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
            ) as? [[String: Any]]
        else { return true }
        let pipProcesses = Set(
            NSWorkspace.shared.runningApplications.filter {
                $0.bundleIdentifier == "com.apple.PIPAgent"
            }.map(\.processIdentifier))
        return windows.contains { window in
            guard let pid = window[kCGWindowOwnerPID as String] as? Int32,
                pipProcesses.contains(pid),
                (window[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                let bounds = window[kCGWindowBounds as String] as? [String: Double]
            else { return false }
            return (bounds["Width"] ?? 0) > 1 && (bounds["Height"] ?? 0) > 1
        }
    }
}
