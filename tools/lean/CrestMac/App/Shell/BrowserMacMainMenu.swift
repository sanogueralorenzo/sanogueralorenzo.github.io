import AppKit

/// The menu bar's top menu. AppKit offers it every key equivalent no view
/// took, and a page's engine hands it each key the page let go. Its items
/// match most of Crest's chords themselves; the shell runs a command whose
/// chord no item matches, such as zoom's ⌘= for the item's ⌘+.
final class BrowserMacMainMenu: NSMenu {
    // MARK: - Variables

    weak var shell: BrowserMacShell?

    // MARK: - Actions - Key equivalents

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if super.performKeyEquivalent(with: event) { return true }
        guard let shell else { return false }
        // AppKit and the engines ask the menu bar about keys on the main
        // thread only.
        nonisolated(unsafe) let event = event
        return MainActor.assumeIsolated { shell.handleShortcut(event, pageSeesFirst: false) }
    }
}
