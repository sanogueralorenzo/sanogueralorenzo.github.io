import AppKit
import Foundation
import Observation

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
  let authCLI = CodexAuthCLIClient()
  let remoteCLI = CodexRemoteCLIClient()
  let menuDataStore = CodexMenuDataStore()
  var remoteLaunchPreference = RemoteLaunchPreference.load()
  var statusItem: NSStatusItem!
  private var isMenuOpen = false
  private var needsRenderAfterMenuClose = false

  func applicationDidFinishLaunching(_ notification: Notification) {
    do {
      try LaunchAgentInstaller.ensureLaunchAgentPlistExists()
    } catch {
      fputs("Warning: failed to configure auto-start: \(error)\n", stderr)
    }

    do {
      try authCLI.startWatcher()
    } catch {
      fputs("Warning: failed to start codex-core auth watcher: \(error)\n", stderr)
    }

    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    statusItem.button?.image = nil
    statusItem.button?.title = "CA"

    let menu = NSMenu()
    menu.delegate = self
    statusItem.menu = menu

    observeMenuDataChanges()
    renderMenu()
    refreshUI()
    startCodexRemoteIfNeededOnLaunch()
  }

  func refreshTitle() {
    let profile = menuDataStore.data.currentProfileName
    let tooltip: String
    if let profile {
      tooltip = "Profiles (\(displayProfileName(profile)))"
    } else {
      tooltip = "Profiles"
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
    menuDataStore.refresh(authCLI: authCLI, remoteCLI: remoteCLI)
  }

  func menuWillOpen(_ menu: NSMenu) {
    isMenuOpen = true
    refreshUI()
  }

  func menuDidClose(_ menu: NSMenu) {
    isMenuOpen = false
    if needsRenderAfterMenuClose {
      needsRenderAfterMenuClose = false
      renderMenu()
    }
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
    alert.messageText = "Codex Menu"
    alert.informativeText = message
    alert.addButton(withTitle: "OK")
    alert.runModal()
  }

  func applicationWillTerminate(_ notification: Notification) {
    try? authCLI.stopWatcher()
  }

  private func renderMenu() {
    refreshTitle()
    if let menu = statusItem.menu {
      rebuildMenu(menu)
    }
  }

  private func observeMenuDataChanges() {
    withObservationTracking {
      _ = menuDataStore.data
    } onChange: { [weak self] in
      DispatchQueue.main.async {
        guard let self else {
          return
        }
        if self.isMenuOpen {
          self.needsRenderAfterMenuClose = true
        } else {
          self.renderMenu()
        }
        self.observeMenuDataChanges()
      }
    }
  }

  private func startCodexRemoteIfNeededOnLaunch() {
    guard remoteLaunchPreference.shouldAutoStart else {
      return
    }

    let remoteCLI = self.remoteCLI
    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      do {
        if try remoteCLI.isRunning() {
          return
        }
        try remoteCLI.start()
      } catch {
        fputs("Warning: failed to auto-start codex-remote: \(error)\n", stderr)
      }

      DispatchQueue.main.async {
        self?.refreshUI()
      }
    }
  }
}

struct RemoteLaunchPreference: Equatable {
  let shouldAutoStart: Bool

  static let disabled = RemoteLaunchPreference(shouldAutoStart: false)
  static let enabled = RemoteLaunchPreference(shouldAutoStart: true)
  private static let key = "remote.shouldAutoStart"

  static func load(defaults: UserDefaults = .standard) -> RemoteLaunchPreference {
    guard defaults.object(forKey: key) != nil else {
      return .enabled
    }
    return RemoteLaunchPreference(shouldAutoStart: defaults.bool(forKey: key))
  }

  func save(defaults: UserDefaults = .standard) {
    defaults.set(shouldAutoStart, forKey: Self.key)
  }
}
