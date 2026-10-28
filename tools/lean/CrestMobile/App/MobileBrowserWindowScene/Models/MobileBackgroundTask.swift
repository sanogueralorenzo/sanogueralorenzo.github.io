import UIKit

/// Keeps the app running after its scenes leave the foreground until `end()`,
/// or until iOS takes the time back, whichever comes first. Without one, iOS
/// may suspend the app as soon as a scene goes to the background.
@MainActor
final class MobileBackgroundTask {
    // MARK: - Variables

    private var identifier = UIBackgroundTaskIdentifier.invalid

    // MARK: - Initializers

    init(named name: String) {
        identifier = UIApplication.shared.beginBackgroundTask(withName: name) { [weak self] in
            self?.end()
        }
    }

    // MARK: - Actions - Lifetime

    func end() {
        guard identifier != .invalid else { return }
        UIApplication.shared.endBackgroundTask(identifier)
        identifier = .invalid
    }
}
