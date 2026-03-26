import AppKit
import Darwin
import Foundation
import Observation
import UserNotifications

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate,
  UNUserNotificationCenterDelegate
{
  let authCLI = CodexAuthCLIClient()
  let remoteCLI = CodexRemoteCLIClient()
  let sessionsCLI = CodexCoreCLIClient()
  let menuDataStore = CodexMenuDataStore()
  var remoteLaunchPreference = RemoteLaunchPreference.load()
  var autoRemoveSettings = AutoRemoveSettings.load()
  let autoRemoveQueue = DispatchQueue(
    label: "io.github.sanogueralorenzo.codex-menubar.auto-remove",
    qos: .utility
  )
  let reviewStatusWatcherQueue = DispatchQueue(
    label: "io.github.sanogueralorenzo.codex-menubar.review-status",
    qos: .utility
  )
  let taskStatusWatcherQueue = DispatchQueue(
    label: "io.github.sanogueralorenzo.codex-menubar.task-status",
    qos: .utility
  )
  var autoRemoveSchedulerTimer: DispatchSourceTimer?
  let autoRemoveIntervalMinutes = 60
  var reviewStatusWatcher: DispatchSourceFileSystemObject?
  var reviewStatusWatcherFileDescriptor: CInt = -1
  var taskStatusWatcher: DispatchSourceFileSystemObject?
  var taskStatusWatcherFileDescriptor: CInt = -1
  var statusItem: NSStatusItem!
  var globalHotKeyController: CodexGlobalHotKeyController?
  private var isMenuOpen = false
  private var needsRenderAfterMenuClose = false
  var codexAgentSettingsWindowController: CodexAgentSettingsWindowController?
  var codexBrowserRunWindowController: CodexBrowserRunWindowController?

  func applicationDidFinishLaunching(_ notification: Notification) {
    let notificationCenter = UNUserNotificationCenter.current()
    notificationCenter.delegate = self

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

    let sessionsCLI = self.sessionsCLI
    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      do {
        try sessionsCLI.startTitleWatcher()
      } catch {
        fputs("Warning: failed to start codex-core thread-title watcher: \(error)\n", stderr)
      }
      DispatchQueue.main.async {
        self?.refreshUI()
      }
    }

    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    statusItem.button?.image = StatusBarIcon.codex()
    statusItem.button?.imagePosition = .imageOnly
    statusItem.button?.title = ""

    let menu = NSMenu()
    menu.delegate = self
    statusItem.menu = menu

    globalHotKeyController = CodexGlobalHotKeyController { [weak self] in
      self?.openRunFromBrowser(nil)
    }
    do {
      try globalHotKeyController?.register()
    } catch {
      fputs("Warning: failed to register global shortcut: \(error)\n", stderr)
    }

    startAutoRemoveScheduler()
    startReviewStatusWatcher()
    startTaskStatusWatcher()
    observeMenuDataChanges()
    renderMenu()
    refreshUI()
    startCodexRemoteIfNeededOnLaunch()
  }

  nonisolated func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification
  ) async -> UNNotificationPresentationOptions {
    [.banner, .list, .sound]
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
    menuDataStore.refresh(
      authCLI: authCLI,
      remoteCLI: remoteCLI,
      sessionsCLI: sessionsCLI)
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

  func showMessage(title: String, message: String) {
    NSApp.activate(ignoringOtherApps: true)

    let alert = NSAlert()
    alert.messageText = title
    alert.informativeText = message
    alert.addButton(withTitle: "OK")
    alert.runModal()
  }

  func showNotification(title: String, message: String) {
    Task {
      let center = UNUserNotificationCenter.current()
      let granted = try await center.requestAuthorization(options: [.alert, .badge, .sound])
      guard granted else {
        return
      }

      let content = UNMutableNotificationContent()
      content.title = title
      content.body = message
      content.sound = .default

      let identifier = "io.github.sanogueralorenzo.codex-menubar.\(UUID().uuidString)"
      let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
      try await center.add(request)
    }
  }

  func applicationWillTerminate(_ notification: Notification) {
    globalHotKeyController?.unregister()
    stopReviewStatusWatcher()
    stopTaskStatusWatcher()
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

  private func startReviewStatusWatcher() {
    stopReviewStatusWatcher()

    let reviewsDirectoryURL = reviewStatusDirectoryURL()
    do {
      try FileManager.default.createDirectory(
        at: reviewsDirectoryURL,
        withIntermediateDirectories: true
      )
    } catch {
      fputs("Warning: failed to create review status directory: \(error)\n", stderr)
      return
    }

    let fileDescriptor = open(reviewsDirectoryURL.path, O_EVTONLY)
    guard fileDescriptor >= 0 else {
      fputs(
        "Warning: failed to watch review status directory: \(reviewsDirectoryURL.path)\n", stderr)
      return
    }

    let watcher = DispatchSource.makeFileSystemObjectSource(
      fileDescriptor: fileDescriptor,
      eventMask: [.write, .rename, .delete, .extend, .attrib],
      queue: reviewStatusWatcherQueue
    )

    watcher.setEventHandler(handler: Self.makeReviewStatusWatcherHandler(appDelegate: self))

    watcher.setCancelHandler { [fileDescriptor] in
      close(fileDescriptor)
    }

    reviewStatusWatcherFileDescriptor = fileDescriptor
    reviewStatusWatcher = watcher
    watcher.resume()
  }

  private func stopReviewStatusWatcher() {
    reviewStatusWatcher?.cancel()
    reviewStatusWatcher = nil
    reviewStatusWatcherFileDescriptor = -1
  }

  private func startTaskStatusWatcher() {
    stopTaskStatusWatcher()

    let tasksDirectoryURL = taskStatusDirectoryURL()
    do {
      try FileManager.default.createDirectory(
        at: tasksDirectoryURL,
        withIntermediateDirectories: true
      )
    } catch {
      fputs("Warning: failed to create task status directory: \(error)\n", stderr)
      return
    }

    let fileDescriptor = open(tasksDirectoryURL.path, O_EVTONLY)
    guard fileDescriptor >= 0 else {
      fputs(
        "Warning: failed to watch task status directory: \(tasksDirectoryURL.path)\n", stderr)
      return
    }

    let watcher = DispatchSource.makeFileSystemObjectSource(
      fileDescriptor: fileDescriptor,
      eventMask: [.write, .rename, .delete, .extend, .attrib],
      queue: taskStatusWatcherQueue
    )

    watcher.setEventHandler(handler: Self.makeReviewStatusWatcherHandler(appDelegate: self))

    watcher.setCancelHandler { [fileDescriptor] in
      close(fileDescriptor)
    }

    taskStatusWatcherFileDescriptor = fileDescriptor
    taskStatusWatcher = watcher
    watcher.resume()
  }

  private func stopTaskStatusWatcher() {
    taskStatusWatcher?.cancel()
    taskStatusWatcher = nil
    taskStatusWatcherFileDescriptor = -1
  }

  private func reviewStatusDirectoryURL() -> URL {
    if let configuredHome = ProcessInfo.processInfo.environment["CODEX_AGENTS_HOME"],
      !configuredHome.isEmpty
    {
      return URL(fileURLWithPath: configuredHome, isDirectory: true)
        .appendingPathComponent("reviews", isDirectory: true)
    }

    return FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent(".codex", isDirectory: true)
      .appendingPathComponent("agents", isDirectory: true)
      .appendingPathComponent("reviews", isDirectory: true)
  }

  private func taskStatusDirectoryURL() -> URL {
    if let configuredHome = ProcessInfo.processInfo.environment["CODEX_AGENTS_HOME"],
      !configuredHome.isEmpty
    {
      return URL(fileURLWithPath: configuredHome, isDirectory: true)
        .appendingPathComponent("tasks", isDirectory: true)
    }

    return FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent(".codex", isDirectory: true)
      .appendingPathComponent("agents", isDirectory: true)
      .appendingPathComponent("tasks", isDirectory: true)
  }

  private nonisolated static func makeReviewStatusWatcherHandler(
    appDelegate: AppDelegate
  ) -> @Sendable () -> Void {
    { [weak appDelegate] in
      Task { @MainActor [weak appDelegate] in
        appDelegate?.refreshUI()
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

struct AutoRemoveSettings: Equatable {
  let olderThanDays: Int?
  let mode: CodexCoreCLIClient.AutoRemoveMode?

  static let supportedDays = [1, 3, 7]
  static let none = AutoRemoveSettings(olderThanDays: nil, mode: nil)

  private static let selectionKey = "threads.autoRemove.selection"

  static func load(defaults: UserDefaults = .standard) -> AutoRemoveSettings {
    guard let selection = defaults.string(forKey: selectionKey) else {
      return .none
    }

    let components = selection.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: true)
    guard components.count == 2,
      let days = Int(components[0]),
      supportedDays.contains(days),
      let mode = CodexCoreCLIClient.AutoRemoveMode(rawValue: String(components[1]))
    else {
      return .none
    }

    return AutoRemoveSettings(olderThanDays: days, mode: mode)
  }

  func save(defaults: UserDefaults = .standard) {
    guard let olderThanDays, let mode else {
      defaults.removeObject(forKey: Self.selectionKey)
      return
    }
    defaults.set("\(olderThanDays):\(mode.rawValue)", forKey: Self.selectionKey)
  }

  var isConfigured: Bool {
    olderThanDays != nil && mode != nil
  }

  func withSelection(days: Int, mode: CodexCoreCLIClient.AutoRemoveMode) -> AutoRemoveSettings {
    AutoRemoveSettings(olderThanDays: days, mode: mode)
  }
}
