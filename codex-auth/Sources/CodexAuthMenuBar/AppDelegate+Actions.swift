import AppKit
import CodexAuthCore
import Foundation

extension AppDelegate {
    @objc func noopHeader(_ sender: Any?) {
        // Intentionally empty: keeps the title row clickable without side effects.
    }

    @objc func addProfileFromCurrent(_ sender: Any?) {
        do {
            if let currentProfileName = try manager.currentProfileName() {
                showCurrentAuthAlreadyRegisteredWarning(profileName: currentProfileName)
                return
            }

            let existingProfiles = try manager.listProfiles()
            guard let name = promptForProfileName(existingProfiles: existingProfiles) else {
                return
            }

            _ = try manager.saveProfile(name: name, source: .current)
            refreshUI()
        } catch {
            showError(error)
        }
    }

    @objc func useNamedProfile(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else {
            return
        }
        let homeDirectory = manager.paths.homeDirectory

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else {
                return
            }
            do {
                let backgroundManager = ProfileManager(homeDirectory: homeDirectory)
                _ = try backgroundManager.applyProfile(name: name)
                DispatchQueue.main.async {
                    self.refreshUI()
                }
            } catch {
                DispatchQueue.main.async {
                    self.showError(error)
                }
            }
        }
    }

    @objc func removeNamedProfile(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else {
            return
        }

        do {
            try manager.removeProfile(name: name)
            refreshUI()
        } catch {
            showError(error)
        }
    }

    @objc func openHelp(_ sender: Any?) {
        guard let url = URL(string: "https://github.com/sanogueralorenzo/sanogueralorenzo.github.io/tree/main/codex-auth") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    @objc func quit(_ sender: Any?) {
        NSApp.terminate(nil)
    }

    private func showCurrentAuthAlreadyRegisteredWarning(profileName: String) {
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = "Add Profile"
        alert.informativeText = """
This Codex Auth is already linked to the \(displayProfileName(profileName)) profile.

Log in with a different account and try again.
"""
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
