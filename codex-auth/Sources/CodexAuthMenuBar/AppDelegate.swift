import AppKit
import CodexAuthCore
import Foundation

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let manager = ProfileManager()
    var statusItem: NSStatusItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            try LaunchAgentInstaller.ensureLaunchAgentPlistExists()
        } catch {
            fputs("Warning: failed to configure auto-start: \(error)\n", stderr)
        }

        do {
            try manager.ensureDirectories()
        } catch {
            showError(error)
        }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "CA"
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        refreshUI()
    }

    func refreshTitle() {
        let profile = try? manager.currentProfileName()
        let title: String
        if let profile, let first = profile.first {
            title = "CA-\(String(first).uppercased())"
        } else {
            title = "CA"
        }
        statusItem.button?.title = title
    }

    func displayProfileName(_ normalizedName: String) -> String {
        let withSpaces = normalizedName.replacingOccurrences(of: "-", with: " ")
        guard let first = withSpaces.first else {
            return withSpaces
        }
        return String(first).uppercased() + withSpaces.dropFirst()
    }

    func refreshUI() {
        refreshTitle()
        if let menu = statusItem.menu {
            rebuildMenu(menu)
        }
    }

    func menuWillOpen(_ menu: NSMenu) {
        refreshUI()
    }

    func showError(_ error: Error) {
        NSApp.activate(ignoringOtherApps: true)

        let message: String
        if let localized = error as? LocalizedError, let text = localized.errorDescription {
            message = text
        } else {
            message = String(describing: error)
        }

        let alert = NSAlert()
        alert.messageText = "Codex Auth"
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
