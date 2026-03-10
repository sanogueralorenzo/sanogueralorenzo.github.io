import AppKit
import Foundation

extension AppDelegate {
    @objc func openCodexApp(_ sender: Any?) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else {
                return
            }

            do {
                try launchCodexApp()
            } catch {
                DispatchQueue.main.async {
                    self.showError(error)
                }
            }
        }
    }

    @objc func noopHeader(_ sender: Any?) {
        // Intentionally empty: keeps the title row clickable without side effects.
    }

    @objc func addProfileFromCurrent(_ sender: Any?) {
        do {
            if let currentProfileName = try authCLI.currentProfileName() {
                showCurrentAuthAlreadyRegisteredWarning(profileName: currentProfileName)
                return
            }

            let existingProfiles = try authCLI.listProfiles()
            guard let name = promptForProfileName(existingProfiles: existingProfiles) else {
                return
            }

            try authCLI.saveProfile(name: name)
            refreshUI()
        } catch {
            showError(error)
        }
    }

    @objc func useNamedProfile(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else {
            return
        }
        let authCLI = self.authCLI
        let remoteCLI = self.remoteCLI

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else {
                return
            }
            do {
                let shouldRestartRemote = try remoteCLI.isRunning()

                try authCLI.useProfile(name: name)

                if shouldRestartRemote {
                    do {
                        try remoteCLI.restart()
                    } catch {
                        throw RemoteRestartWarning(profileName: name, underlyingError: error)
                    }
                }

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
            try authCLI.removeProfile(name: name)
            refreshUI()
        } catch {
            showError(error)
        }
    }

    @objc func removeStaleSessions(_ sender: Any?) {
        let sessionsCLI = self.sessionsCLI
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else {
                return
            }
            do {
                let staleByDays = try fetchStaleSessionsByDays(using: sessionsCLI)
                DispatchQueue.main.async {
                    let hasAnyStaleSessions = staleByDays.values.contains { !$0.isEmpty }
                    guard hasAnyStaleSessions else {
                        self.showError(CodexSessionsCLIClient.Error(message: "No stale codex threads found for 1/3/7 day windows."))
                        return
                    }

                    guard let selection = self.promptForStaleSessionRemoval(staleByDays: staleByDays) else {
                        return
                    }

                    let sessionsCLI = self.sessionsCLI
                    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                        guard let self else {
                            return
                        }
                        do {
                            try sessionsCLI.deleteSessions(ids: selection.sessionIDs)
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
            } catch {
                DispatchQueue.main.async {
                    self.showError(error)
                }
            }
        }
    }

    @objc func mergeSessions(_ sender: Any?) {
        let sessionsCLI = self.sessionsCLI
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else {
                return
            }
            do {
                let sessions = try sessionsCLI.listActiveSessions()
                DispatchQueue.main.async {
                    guard sessions.count >= 2 else {
                        self.showError(CodexSessionsCLIClient.Error(message: "Need at least two active threads to merge."))
                        return
                    }

                    guard let selection = self.promptForSessionMergeSelection(sessions: sessions) else {
                        return
                    }

                    let sessionsCLI = self.sessionsCLI
                    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                        guard let self else {
                            return
                        }
                        do {
                            try sessionsCLI.mergeSessions(targetID: selection.targetID, mergeID: selection.mergerID)
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
            } catch {
                DispatchQueue.main.async {
                    self.showError(error)
                }
            }
        }
    }

    @objc func openHelp(_ sender: Any?) {
        guard let url = URL(string: "https://github.com/sanogueralorenzo/sanogueralorenzo.github.io/tree/main/codex-menubar") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    @objc func installCodexRemote(_ sender: Any?) {
        do {
            switch try remoteCLI.installAction() {
            case .openGuide(let guideURL):
                NSWorkspace.shared.open(guideURL)
            case .runInstall:
                try remoteCLI.install()
            }
            refreshUI()
        } catch {
            showError(error)
        }
    }

    @objc func startCodexRemote(_ sender: Any?) {
        let remoteCLI = self.remoteCLI
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else {
                return
            }
            do {
                try remoteCLI.start()
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

    @objc func stopCodexRemote(_ sender: Any?) {
        do {
            try remoteCLI.stop()
            refreshUI()
        } catch {
            showError(error)
        }
    }

    @objc func createCodexAgent(_ sender: Any?) {
        // Intentionally no-op placeholder for upcoming Codex Agent flow.
    }

    @objc func viewCodexAgentTask(_ sender: NSMenuItem) {
        // MOCK placeholder: this will open real task details when agent backend is integrated.
    }

    @objc func togglePauseCodexAgentTask(_ sender: NSMenuItem) {
        // MOCK placeholder: this will pause/resume the selected running task.
    }

    @objc func deleteCodexAgentTask(_ sender: NSMenuItem) {
        // MOCK placeholder: this will delete/stop the selected task.
    }

    @objc func rerunCodexAgentTask(_ sender: NSMenuItem) {
        // MOCK placeholder: this will re-queue the selected completed task.
    }

    @objc func openCodexAgentSettings(_ sender: Any?) {
        // MOCK placeholder: this will open Codex Agent settings.
    }

    @objc func quit(_ sender: Any?) {
        let remoteCLI = self.remoteCLI
        let sessionsCLI = self.sessionsCLI
        let authCLI = self.authCLI

        DispatchQueue.global(qos: .userInitiated).async {
            if (try? remoteCLI.isRunning()) == true {
                try? remoteCLI.stop()
            }

            try? sessionsCLI.stopTitleWatcher()
            try? authCLI.stopWatcher()
            try? terminateCodexAppIfRunning()

            DispatchQueue.main.async {
                NSApp.terminate(nil)
            }
        }
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

private func launchCodexApp() throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    process.arguments = ["-a", "Codex"]

    let stderr = Pipe()
    process.standardError = stderr

    try process.run()
    process.waitUntilExit()

    guard process.terminationStatus == 0 else {
        let errorOutput = String(
            data: stderr.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        )?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if errorOutput.isEmpty {
            throw CodexAppLaunchError(message: "Failed to open Codex app.")
        }

        throw CodexAppLaunchError(message: errorOutput)
    }
}

private func terminateCodexAppIfRunning() throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
    process.arguments = ["-f", "/Codex.app/Contents/"]

    let stderr = Pipe()
    process.standardError = stderr

    try process.run()
    process.waitUntilExit()

    // pkill returns 1 when no matching process exists.
    guard process.terminationStatus == 0 || process.terminationStatus == 1 else {
        let errorOutput = String(
            data: stderr.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        )?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if errorOutput.isEmpty {
            throw CodexAppTerminationError(message: "Failed to terminate Codex app.")
        }

        throw CodexAppTerminationError(message: errorOutput)
    }
}

private struct CodexAppLaunchError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

private struct CodexAppTerminationError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

private func fetchStaleSessionsByDays(using sessionsCLI: CodexSessionsCLIClient) throws -> [Int: [CodexSessionsCLIClient.SessionOption]] {
    var result: [Int: [CodexSessionsCLIClient.SessionOption]] = [:]
    for days in [1, 3, 7] {
        result[days] = try sessionsCLI.listStaleSessions(olderThanDays: days)
    }
    return result
}

private struct RemoteRestartWarning: LocalizedError {
    let profileName: String
    let underlyingError: Error

    var errorDescription: String? {
        let message: String
        if let localized = underlyingError as? LocalizedError,
           let description = localized.errorDescription {
            message = description
        } else {
            message = String(describing: underlyingError)
        }
        return "Profile '\(profileName)' was applied, but Codex Remote failed to restart.\n\n\(message)"
    }
}
