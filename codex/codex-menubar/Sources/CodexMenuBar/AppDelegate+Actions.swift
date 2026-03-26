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

  @objc func clearAutoRemoveSelection(_ sender: Any?) {
    applyAutoRemoveSettings(.none)
  }

  @objc func runAutoRemoveNow(_ sender: Any?) {
    let sessionsCLI = self.sessionsCLI

    autoRemoveQueue.async { [weak self] in
      guard let self else {
        return
      }

      var operationError: Error?
      do {
        if try isCodexAppRunning() {
          try terminateCodexAppIfRunning()
        }
        try sessionsCLI.runAutoRemove(olderThanDays: 0, mode: .delete)
      } catch {
        operationError = error
      }

      var restartError: Error?
      do {
        try restartCodexApp()
      } catch {
        restartError = error
      }

      DispatchQueue.main.async {
        if let operationError {
          self.showError(operationError)
          return
        }
        if let restartError {
          self.showError(restartError)
          return
        }
        self.refreshUI()
      }
    }
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
      let mode = CodexCoreCLIClient.AutoRemoveMode(rawValue: String(components[1]))
    else {
      return
    }

    let nextSettings = autoRemoveSettings.withSelection(days: days, mode: mode)
    applyAutoRemoveSettings(nextSettings)
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
    stopAutoRemoveScheduler()

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

  func startAutoRemoveScheduler() {
    stopAutoRemoveScheduler()
    guard let olderThanDays = autoRemoveSettings.olderThanDays,
      let mode = autoRemoveSettings.mode
    else {
      return
    }
    let sessionsCLI = self.sessionsCLI
    let handler = Self.makeAutoRemovePassHandler(
      sessionsCLI: sessionsCLI,
      olderThanDays: olderThanDays,
      mode: mode
    )
    scheduleAutoRemoveRun(handler: handler)

    let intervalSeconds = max(60, autoRemoveIntervalMinutes * 60)

    let timer = DispatchSource.makeTimerSource(queue: autoRemoveQueue)
    timer.schedule(
      deadline: .now() + .seconds(intervalSeconds),
      repeating: .seconds(intervalSeconds)
    )
    timer.setEventHandler(handler: handler)
    timer.resume()
    autoRemoveSchedulerTimer = timer
  }

  func stopAutoRemoveScheduler() {
    autoRemoveSchedulerTimer?.cancel()
    autoRemoveSchedulerTimer = nil
  }

  private func applyAutoRemoveSettings(_ nextSettings: AutoRemoveSettings) {
    guard nextSettings != autoRemoveSettings else {
      return
    }

    autoRemoveSettings = nextSettings
    autoRemoveSettings.save()
    if nextSettings.isConfigured {
      startAutoRemoveScheduler()
    } else {
      stopAutoRemoveScheduler()
    }
    refreshUI()
  }

  private func scheduleAutoRemoveRun(handler: @escaping @Sendable () -> Void) {
    autoRemoveQueue.async(execute: handler)
  }

  private nonisolated static func makeAutoRemovePassHandler(
    sessionsCLI: CodexCoreCLIClient,
    olderThanDays: Int,
    mode: CodexCoreCLIClient.AutoRemoveMode
  ) -> @Sendable () -> Void {
    {
      runAutoRemovePass(
        sessionsCLI: sessionsCLI,
        olderThanDays: olderThanDays,
        mode: mode
      )
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

private func restartCodexApp() throws {
  if try isCodexAppRunning() {
    try terminateCodexAppIfRunning()
  }
  try launchCodexApp()
}

private func isCodexAppRunning() throws -> Bool {
  let process = Process()
  process.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
  process.arguments = ["-f", "/Codex.app/Contents/"]

  let stderr = Pipe()
  process.standardError = stderr

  try process.run()
  process.waitUntilExit()

  if process.terminationStatus == 0 {
    return true
  }
  if process.terminationStatus == 1 {
    return false
  }

  let errorOutput =
    String(
      data: stderr.fileHandleForReading.readDataToEndOfFile(),
      encoding: .utf8
    )?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

  if errorOutput.isEmpty {
    throw CodexAppStatusError(message: "Failed to determine Codex app status.")
  }

  throw CodexAppStatusError(message: errorOutput)
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

private struct CodexAppStatusError: LocalizedError {
  let message: String
  var errorDescription: String? { message }
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
  sessionsCLI: CodexCoreCLIClient,
  olderThanDays: Int,
  mode: CodexCoreCLIClient.AutoRemoveMode
) {
  do {
    try sessionsCLI.runAutoRemove(olderThanDays: olderThanDays, mode: mode)
  } catch {
    fputs(
      "Warning: auto-remove run failed (days=\(olderThanDays), mode=\(mode.rawValue)): \(error)\n",
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
      let description = localized.errorDescription
    {
      message = description
    } else {
      message = String(describing: underlyingError)
    }
    return "Profile '\(profileName)' was applied, but Codex Remote failed to restart.\n\n\(message)"
  }
}
