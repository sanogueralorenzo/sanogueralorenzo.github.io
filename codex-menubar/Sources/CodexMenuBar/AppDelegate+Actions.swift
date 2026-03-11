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

    @objc func setAutoRemoveSelection(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? String else {
            return
        }

        let components = value.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: true)
        guard components.count == 2,
              let days = Int(components[0]),
              AutoRemoveSettings.supportedDays.contains(days),
              let mode = CodexSessionsCLIClient.AutoRemoveMode(rawValue: String(components[1])) else {
            return
        }

        let nextSettings = autoRemoveSettings.withDays(days).withMode(mode)
        guard nextSettings.olderThanDays != autoRemoveSettings.olderThanDays
                || nextSettings.mode != autoRemoveSettings.mode else {
            return
        }

        autoRemoveSettings = nextSettings
        autoRemoveSettings.save()
        startAutoRemoveWatcher()
        refreshUI()
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
        stopAutoRemoveWatcher()

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

    func startAutoRemoveWatcher() {
        stopAutoRemoveWatcher()
        scheduleAutoRemoveRun(using: autoRemoveSettings)

        let settings = autoRemoveSettings
        let sessionsCLI = self.sessionsCLI
        let intervalSeconds = max(60, autoRemoveIntervalMinutes * 60)

        let timer = DispatchSource.makeTimerSource(queue: autoRemoveQueue)
        timer.schedule(
            deadline: .now() + .seconds(intervalSeconds),
            repeating: .seconds(intervalSeconds)
        )
        timer.setEventHandler {
            runAutoRemovePass(sessionsCLI: sessionsCLI, settings: settings)
        }
        timer.resume()
        autoRemoveTimer = timer
    }

    func stopAutoRemoveWatcher() {
        autoRemoveTimer?.cancel()
        autoRemoveTimer = nil
    }

    private func scheduleAutoRemoveRun(using settings: AutoRemoveSettings) {
        let sessionsCLI = self.sessionsCLI
        autoRemoveQueue.async {
            runAutoRemovePass(sessionsCLI: sessionsCLI, settings: settings)
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

private func runAutoRemovePass(
    sessionsCLI: CodexSessionsCLIClient,
    settings: AutoRemoveSettings
) {
    do {
        try sessionsCLI.runAutoRemove(
            olderThanDays: settings.olderThanDays,
            mode: settings.mode
        )
    } catch {
        fputs(
            "Warning: auto-remove run failed (days=\(settings.olderThanDays), mode=\(settings.mode.rawValue)): \(error)\n",
            stderr
        )
    }
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
