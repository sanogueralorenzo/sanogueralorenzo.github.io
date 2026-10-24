import AppKit
import Observation
import SwiftUI

/// Applies the person's appearance choice to the whole application, so every
/// window, menu, popover and page draws light or dark with it, and reports the
/// scheme that results back to the shared views as the system changes it.
@MainActor
final class BrowserMacAppearance {
    // MARK: - Static Variables

    /// The application's one appearance.
    static let shared = BrowserMacAppearance()

    // MARK: - Variables

    private let store = BrowserDeviceAppearanceStore.shared
    private var effectiveAppearanceObservation: NSKeyValueObservation?

    // MARK: - Initializers

    private init() {}

    // MARK: - Actions - Starting

    /// Applies the choice now, and from now on whenever it or the system's
    /// own appearance changes.
    func start() {
        guard effectiveAppearanceObservation == nil else { return }
        effectiveAppearanceObservation = NSApp.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in
            Task { @MainActor in self?.reportShownScheme() }
        }
        followMode()
        reportShownScheme()
    }

    // MARK: - Actions - Appearance

    /// Sets the application's appearance from the chosen mode now and
    /// whenever the mode changes. Following the system leaves it unset.
    private func followMode() {
        withObservationTracking {
            NSApp.appearance = store.mode.colorScheme.flatMap { NSAppearance(named: $0 == .dark ? .darkAqua : .aqua) }
        } onChange: { [weak self] in
            Task { @MainActor in self?.followMode() }
        }
    }

    /// Tells the shared views which scheme the application draws in now.
    private func reportShownScheme() {
        let isDark = NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let scheme: ColorScheme = isDark ? .dark : .light
        guard store.shownColorScheme != scheme else { return }
        store.shownColorScheme = scheme
    }
}
