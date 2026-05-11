import AppKit
import Foundation

extension AppDelegate {
  @objc func clearAgentRuns(_ sender: Any?) {
    let data = menuDataStore.data
    let clearableSpikeJobs = data.spikeJobs.filter { $0.status != .inProgress }
    let clearableTaskJobs = data.taskJobs.filter { $0.status != .inProgress }
    let clearableReviewJobs = data.reviewJobs.filter { $0.status != .inProgress }

    guard
      !clearableSpikeJobs.isEmpty || !clearableTaskJobs.isEmpty || !clearableReviewJobs.isEmpty
    else {
      return
    }

    let spikesDirectoryURL = spikeStatusDirectoryURL()
    let tasksDirectoryURL = taskStatusDirectoryURL()
    let reviewsDirectoryURL = reviewStatusDirectoryURL()

    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      guard let self else {
        return
      }

      do {
        try Self.removeAgentRunArtifacts(
          spikesDirectoryURL: spikesDirectoryURL,
          tasksDirectoryURL: tasksDirectoryURL,
          reviewsDirectoryURL: reviewsDirectoryURL,
          spikeJobs: clearableSpikeJobs,
          taskJobs: clearableTaskJobs,
          reviewJobs: clearableReviewJobs
        )
        DispatchQueue.main.async {
          self.refreshUI()
        }
      } catch {
        DispatchQueue.main.async {
          self.showError(error)
          self.refreshUI()
        }
      }
    }
  }

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

  @objc func openHelp(_ sender: Any?) {
    guard
      let url = URL(
        string:
          "https://github.com/sanogueralorenzo/sanogueralorenzo.github.io/tree/main/codex/codex-menubar"
      )
    else {
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
          self.remoteLaunchPreference = .enabled
          self.remoteLaunchPreference.save()
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
      remoteLaunchPreference = .disabled
      remoteLaunchPreference.save()
      refreshUI()
    } catch {
      showError(error)
    }
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

  private nonisolated static func removeAgentRunArtifacts(
    spikesDirectoryURL: URL,
    tasksDirectoryURL: URL,
    reviewsDirectoryURL: URL,
    spikeJobs: [CodexCoreCLIClient.SpikeJob],
    taskJobs: [CodexCoreCLIClient.TaskJob],
    reviewJobs: [CodexCoreCLIClient.ReviewJob]
  ) throws {
    let fileManager = FileManager.default

    for job in spikeJobs {
      let path = spikesDirectoryURL.appendingPathComponent("\(job.id).json")
      if fileManager.fileExists(atPath: path.path) {
        try fileManager.removeItem(at: path)
      }
    }

    for job in taskJobs {
      let path = tasksDirectoryURL.appendingPathComponent("\(job.id).json")
      if fileManager.fileExists(atPath: path.path) {
        try fileManager.removeItem(at: path)
      }
    }

    for job in reviewJobs {
      let path = reviewsDirectoryURL.appendingPathComponent(job.id, isDirectory: true)
      if fileManager.fileExists(atPath: path.path) {
        try fileManager.removeItem(at: path)
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

private func launchCodexApp() throws {
  let process = Process()
  process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
  process.arguments = ["-a", "Codex"]

  let stderr = Pipe()
  process.standardError = stderr

  try process.run()
  process.waitUntilExit()

  guard process.terminationStatus == 0 else {
    let errorOutput =
      String(
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

private struct CodexAppLaunchError: LocalizedError {
  let message: String
  var errorDescription: String? { message }
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
