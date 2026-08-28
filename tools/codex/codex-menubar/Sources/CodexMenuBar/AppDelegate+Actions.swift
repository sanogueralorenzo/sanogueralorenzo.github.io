import AppKit
import Foundation

extension AppDelegate {
  @objc func noopHeader(_ sender: Any?) {
    // Intentionally empty: keeps the title row clickable without side effects.
  }

  @objc func addProfileFromCurrent(_ sender: Any?) {
    let authCLI = self.authCLI

    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      do {
        let currentProfileName = try authCLI.currentProfileName()
        let existingProfiles = try authCLI.listProfiles()

        DispatchQueue.main.async {
          guard let self else {
            return
          }

          if let currentProfileName {
            self.showCurrentAuthAlreadyRegisteredWarning(profileName: currentProfileName)
            return
          }

          guard let name = self.promptForProfileName(existingProfiles: existingProfiles) else {
            return
          }

          DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
              try authCLI.saveProfile(name: name)
              DispatchQueue.main.async {
                self?.refreshUI()
              }
            } catch {
              DispatchQueue.main.async {
                self?.showError(error)
              }
            }
          }
        }
      } catch {
        DispatchQueue.main.async {
          self?.showError(error)
        }
      }
    }
  }

  @objc func useNamedProfile(_ sender: NSMenuItem) {
    guard let name = sender.representedObject as? String else {
      return
    }
    let authCLI = self.authCLI
    let remoteCLI = self.remoteCLI

    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
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
          self?.refreshUI()
        }
      } catch {
        DispatchQueue.main.async {
          self?.showError(error)
        }
      }
    }
  }

  @objc func removeNamedProfile(_ sender: NSMenuItem) {
    guard let name = sender.representedObject as? String else {
      return
    }
    let authCLI = self.authCLI

    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      do {
        try authCLI.removeProfile(name: name)
        DispatchQueue.main.async {
          self?.refreshUI()
        }
      } catch {
        DispatchQueue.main.async {
          self?.showError(error)
        }
      }
    }
  }

  @objc func installCodexRemote(_ sender: Any?) {
    let remoteCLI = self.remoteCLI

    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      do {
        switch try remoteCLI.installAction() {
        case .openGuide(let guideURL):
          DispatchQueue.main.async {
            NSWorkspace.shared.open(guideURL)
            self?.refreshUI()
          }
        case .runInstall:
          try remoteCLI.install()
          DispatchQueue.main.async {
            self?.refreshUI()
          }
        }
      } catch {
        DispatchQueue.main.async {
          self?.showError(error)
        }
      }
    }
  }

  @objc func startCodexRemote(_ sender: Any?) {
    let remoteCLI = self.remoteCLI
    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      do {
        try remoteCLI.start()
        DispatchQueue.main.async {
          guard let self else {
            return
          }
          self.remoteLaunchPreference = .enabled
          self.remoteLaunchPreference.save()
          self.refreshUI()
        }
      } catch {
        DispatchQueue.main.async {
          self?.showError(error)
        }
      }
    }
  }

  @objc func stopCodexRemote(_ sender: Any?) {
    let remoteCLI = self.remoteCLI

    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      do {
        try remoteCLI.stop()
        DispatchQueue.main.async {
          guard let self else {
            return
          }
          self.remoteLaunchPreference = .disabled
          self.remoteLaunchPreference.save()
          self.refreshUI()
        }
      } catch {
        DispatchQueue.main.async {
          self?.showError(error)
        }
      }
    }
  }

  @objc func quit(_ sender: Any?) {
    let remoteCLI = self.remoteCLI
    let authCLI = self.authCLI

    DispatchQueue.global(qos: .userInitiated).async {
      if (try? remoteCLI.isRunning()) == true {
        try? remoteCLI.stop()
      }

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
      This auth is already linked to the \(displayProfileName(profileName)) profile.

      Log in with a different account and try again.
      """
    alert.addButton(withTitle: "OK")
    alert.runModal()
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

  guard process.terminationStatus == 0 || process.terminationStatus == 1 else {
    let errorOutput =
      String(
        data: stderr.fileHandleForReading.readDataToEndOfFile(),
        encoding: .utf8
      )?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

    if errorOutput.isEmpty {
      throw CodexAppTerminationError(message: "Failed to terminate Codex app.")
    }

    throw CodexAppTerminationError(message: errorOutput)
  }
}

private struct CodexAppTerminationError: LocalizedError {
  let message: String
  var errorDescription: String? { message }
}

private struct RemoteRestartWarning: LocalizedError {
  let profileName: String
  let underlyingError: Error

  var errorDescription: String? {
    let message: String
    if let localized = underlyingError as? LocalizedError,
      let description = localized.errorDescription
    {
      message = description
    } else {
      message = String(describing: underlyingError)
    }
    return "Profile '\(profileName)' was applied, but Codex Remote failed to restart.\n\n\(message)"
  }
}
