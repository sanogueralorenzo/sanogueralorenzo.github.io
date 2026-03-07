import AppKit
import CodexAuthCore
import Foundation

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let manager = ProfileManager()
    var statusItem: NSStatusItem!
    private var authSyncMonitor: AuthSyncMonitor?

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

        do {
            _ = try manager.syncActiveProfileWithCurrentAuth()
        } catch {
            fputs("Warning: failed to sync active profile with current auth: \(error)\n", stderr)
        }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = StatusBarIcon.codex()
        statusItem.button?.imagePosition = .imageOnly
        statusItem.button?.title = ""
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        authSyncMonitor = AuthSyncMonitor(
            homeDirectory: manager.paths.homeDirectory,
            onDidSync: { [weak self] in
                self?.refreshUI()
            },
            onError: { error in
                fputs("Warning: auth sync monitor error: \(error)\n", stderr)
            }
        )
        authSyncMonitor?.start()

        refreshUI()
    }

    func refreshTitle() {
        let profile = try? manager.currentProfileName()
        let tooltip: String
        if let profile {
            tooltip = "Codex Auth (\(displayProfileName(profile)))"
        } else {
            tooltip = "Codex Auth"
        }
        statusItem.button?.toolTip = tooltip
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

    func applicationWillTerminate(_ notification: Notification) {
        authSyncMonitor?.stop()
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
