import AppKit
import Foundation

@MainActor
private final class IntegrationStatusRowView: NSView {
  private let pillView = NSView()
  private let pillLabel = NSTextField(labelWithString: "")
  private let summaryLabel = NSTextField(labelWithString: "")
  private let detailLabel = NSTextField(labelWithString: "")

  init(toolName: String) {
    super.init(frame: NSRect(x: 0, y: 0, width: 460, height: 38))

    pillView.wantsLayer = true
    pillView.layer?.cornerRadius = 10
    pillView.layer?.masksToBounds = true
    pillView.frame = NSRect(x: 0, y: 17, width: 44, height: 20)
    addSubview(pillView)

    pillLabel.font = .boldSystemFont(ofSize: 11)
    pillLabel.alignment = .center
    pillLabel.textColor = .white
    pillLabel.stringValue = toolName
    pillLabel.frame = NSRect(x: 0, y: 3, width: 44, height: 14)
    pillView.addSubview(pillLabel)

    summaryLabel.font = .systemFont(ofSize: 12, weight: .medium)
    summaryLabel.frame = NSRect(x: 56, y: 18, width: 404, height: 16)
    addSubview(summaryLabel)

    detailLabel.font = .systemFont(ofSize: 11)
    detailLabel.textColor = .secondaryLabelColor
    detailLabel.lineBreakMode = .byTruncatingTail
    detailLabel.frame = NSRect(x: 56, y: 0, width: 404, height: 16)
    addSubview(detailLabel)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func apply(status: IntegrationStatus) {
    switch status.state {
    case .checking:
      pillView.layer?.backgroundColor = NSColor.tertiaryLabelColor.cgColor
      summaryLabel.stringValue = "Checking..."
      detailLabel.stringValue = ""
    case .ready(let summary, let detail):
      pillView.layer?.backgroundColor = NSColor.systemGreen.cgColor
      summaryLabel.stringValue = summary
      detailLabel.stringValue = detail ?? ""
    case .actionNeeded(let summary, let detail):
      pillView.layer?.backgroundColor = NSColor.systemOrange.cgColor
      summaryLabel.stringValue = summary
      detailLabel.stringValue = detail
    case .missing(let summary, let detail):
      pillView.layer?.backgroundColor = NSColor.systemRed.cgColor
      summaryLabel.stringValue = summary
      detailLabel.stringValue = detail
    case .error(let summary, let detail):
      pillView.layer?.backgroundColor = NSColor.systemRed.cgColor
      summaryLabel.stringValue = summary
      detailLabel.stringValue = detail
    }
  }
}

struct CodexAgentSettingsSelection {
  let reviewMode: CodexCoreCLIClient.ReviewMode
  let allowedRepos: [String]
  let allowedProjectIDs: [Int]
}

@MainActor
final class CodexAgentSettingsWindowController: NSWindowController, NSTableViewDataSource,
  NSTableViewDelegate, NSWindowDelegate, NSSearchFieldDelegate
{
  private enum ListKind {
    case repos
    case projects
  }

  private let ghStatusRow = IntegrationStatusRowView(toolName: "gh")
  private let acliStatusRow = IntegrationStatusRowView(toolName: "acli")
  private let cancelButton = NSButton(title: "Cancel", target: nil, action: nil)
  private let saveButton = NSButton(title: "Save", target: nil, action: nil)
  private let reviewModePopUp = NSPopUpButton()
  private let sourcePicker = NSSegmentedControl(
    labels: ["GitHub Repositories", "Jira Projects"], trackingMode: .selectOne, target: nil,
    action: nil)
  private let searchField = NSSearchField()
  private let listProgressIndicator = NSProgressIndicator()
  private let listHint = NSTextField(labelWithString: "")
  private let tableView = NSTableView()
  private let scrollView = NSScrollView()

  private let onSave: (CodexAgentSettingsSelection) -> Void
  private let onClose: () -> Void

  private var repos: [String] = []
  private var filteredRepos: [String] = []
  private var selectedRepos: Set<String> = []
  private var projects: [CodexCoreCLIClient.AvailableProject] = []
  private var filteredProjects: [CodexCoreCLIClient.AvailableProject] = []
  private var selectedProjectIDs: Set<Int> = []
  private var selectedReviewMode: CodexCoreCLIClient.ReviewMode = .publish
  private var activeListKind: ListKind = .repos
  private var repoSearchQuery = ""
  private var projectSearchQuery = ""
  private var configLoaded = false
  private var reposLoaded = false
  private var projectsLoaded = false
  private var reposLoadErrorMessage: String?
  private var projectsLoadErrorMessage: String?
  private let horizontalInset: CGFloat = 20
  private let contentWidth: CGFloat = 460

  init(onSave: @escaping (CodexAgentSettingsSelection) -> Void, onClose: @escaping () -> Void) {
    self.onSave = onSave
    self.onClose = onClose

    let panel = NSPanel(
      contentRect: NSRect(x: 0, y: 0, width: 500, height: 760),
      styleMask: [.titled, .closable, .resizable],
      backing: .buffered,
      defer: false
    )
    panel.title = "Agents Settings"
    panel.isFloatingPanel = true
    panel.center()
    panel.minSize = NSSize(width: 500, height: 640)
    panel.setFrameAutosaveName("CodexAgentSettingsPanel")
    super.init(window: panel)
    panel.delegate = self

    buildUI(in: panel)
    setLoading()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func present() {
    NSApp.activate(ignoringOtherApps: true)
    showWindow(nil)
    window?.makeKeyAndOrderFront(nil)
  }

  func setLoading() {
    configLoaded = false
    reposLoaded = false
    projectsLoaded = false
    reposLoadErrorMessage = nil
    projectsLoadErrorMessage = nil
    selectedReviewMode = .publish
    reviewModePopUp.selectItem(at: 0)
    saveButton.isEnabled = false
    ghStatusRow.apply(status: IntegrationStatus(toolName: "gh", state: .checking))
    acliStatusRow.apply(status: IntegrationStatus(toolName: "acli", state: .checking))
    applyReposSearchFilter()
    applyProjectsSearchFilter()
    updateListChrome()
    tableView.reloadData()
  }

  func applyCurrentConfig(_ currentConfig: CodexCoreCLIClient.AgentsConfig) {
    configLoaded = true
    selectedReviewMode = currentConfig.reviewMode
    reviewModePopUp.selectItem(withTitle: reviewModeTitle(for: currentConfig.reviewMode))
    selectedRepos = Set(currentConfig.allowedRepos)
    selectedProjectIDs = Set(currentConfig.allowedProjects)
    updateSaveButtonState()
    tableView.reloadData()
  }

  func applyAvailableRepos(_ availableRepos: [CodexCoreCLIClient.AvailableRepo]) {
    reposLoaded = true
    reposLoadErrorMessage = nil
    repos = availableRepos.map(\.fullName)
    applyReposSearchFilter()
    updateSaveButtonState()
    updateListChrome()
    tableView.reloadData()
  }

  func applyAvailableProjects(_ availableProjects: [CodexCoreCLIClient.AvailableProject]) {
    projectsLoaded = true
    projectsLoadErrorMessage = nil
    projects = availableProjects
    applyProjectsSearchFilter()
    updateSaveButtonState()
    updateListChrome()
    tableView.reloadData()
  }

  func applyIntegrationStatuses(_ statuses: [IntegrationStatus]) {
    for status in statuses {
      switch status.toolName {
      case "gh":
        ghStatusRow.apply(status: status)
      case "acli":
        acliStatusRow.apply(status: status)
      default:
        break
      }
    }
  }

  func applyLoadError(_ message: String) {
    reposLoadErrorMessage = message
    projectsLoadErrorMessage = message
    reposLoaded = false
    projectsLoaded = false
    repos = []
    projects = []
    filteredRepos = []
    filteredProjects = []
    saveButton.isEnabled = false
    updateListChrome()
    tableView.reloadData()
  }

  @objc func save(_ sender: Any?) {
    guard configLoaded && reposLoaded && projectsLoaded else {
      return
    }
    onSave(
      CodexAgentSettingsSelection(
        reviewMode: selectedReviewMode,
        allowedRepos: selectedRepos.sorted(),
        allowedProjectIDs: selectedProjectIDs.sorted()
      )
    )
    close()
  }

  @objc func cancel(_ sender: Any?) {
    close()
  }

  func windowWillClose(_ notification: Notification) {
    onClose()
  }

  func numberOfRows(in tableView: NSTableView) -> Int {
    max(currentRowCount, 1)
  }

  func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView?
  {
    if let emptyStateView = emptyStateView() {
      return emptyStateView
    }

    let identifier = NSUserInterfaceItemIdentifier(
      rawValue: activeListKind == .repos ? "repo-cell" : "project-cell")
    let cellView =
      tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView
      ?? makeSelectionCellView(identifier: identifier.rawValue)
    let button = cellView.subviews.compactMap({ $0 as? NSButton }).first!
    button.target = self

    switch activeListKind {
    case .repos:
      let repo = filteredRepos[row]
      button.action = #selector(toggleRepoSelection(_:))
      button.state = selectedRepos.contains(repo) ? .on : .off
      button.identifier = NSUserInterfaceItemIdentifier(rawValue: repo)
      button.title = repo
    case .projects:
      let project = filteredProjects[row]
      button.action = #selector(toggleProjectSelection(_:))
      button.state = selectedProjectIDs.contains(project.id) ? .on : .off
      button.identifier = NSUserInterfaceItemIdentifier(rawValue: String(project.id))
      button.title = project.displayName
    }

    return cellView
  }

  func controlTextDidChange(_ notification: Notification) {
    let query = searchField.stringValue
    switch activeListKind {
    case .repos:
      repoSearchQuery = query
      applyReposSearchFilter()
    case .projects:
      projectSearchQuery = query
      applyProjectsSearchFilter()
    }
    tableView.reloadData()
  }

  @objc private func toggleRepoSelection(_ sender: NSButton) {
    guard let repo = sender.identifier?.rawValue else {
      return
    }
    if sender.state == .on {
      selectedRepos.insert(repo)
    } else {
      selectedRepos.remove(repo)
    }
  }

  @objc private func toggleProjectSelection(_ sender: NSButton) {
    guard let rawValue = sender.identifier?.rawValue, let projectID = Int(rawValue) else {
      return
    }
    if sender.state == .on {
      selectedProjectIDs.insert(projectID)
    } else {
      selectedProjectIDs.remove(projectID)
    }
  }

  @objc private func reviewModeChanged(_ sender: NSPopUpButton) {
    selectedReviewMode = sender.indexOfSelectedItem == 1 ? .pending : .publish
  }

  @objc private func sourcePickerChanged(_ sender: NSSegmentedControl) {
    activeListKind = sender.selectedSegment == 1 ? .projects : .repos
    searchField.stringValue = activeQuery
    updateListChrome()
    tableView.reloadData()
  }

  private func buildUI(in panel: NSPanel) {
    guard let contentView = panel.contentView else {
      return
    }

    let integrationsTitle = NSTextField(labelWithString: "Integrations")
    integrationsTitle.font = .boldSystemFont(ofSize: NSFont.systemFontSize)
    integrationsTitle.frame = NSRect(x: horizontalInset, y: 700, width: contentWidth, height: 20)
    integrationsTitle.autoresizingMask = [.width, .minYMargin]
    contentView.addSubview(integrationsTitle)

    ghStatusRow.frame = NSRect(x: horizontalInset, y: 650, width: contentWidth, height: 38)
    ghStatusRow.autoresizingMask = [.width, .minYMargin]
    contentView.addSubview(ghStatusRow)

    acliStatusRow.frame = NSRect(x: horizontalInset, y: 604, width: contentWidth, height: 38)
    acliStatusRow.autoresizingMask = [.width, .minYMargin]
    contentView.addSubview(acliStatusRow)

    let integrationsDivider = NSBox(
      frame: NSRect(x: horizontalInset, y: 578, width: contentWidth, height: 1))
    integrationsDivider.boxType = .separator
    integrationsDivider.autoresizingMask = [.width, .minYMargin]
    contentView.addSubview(integrationsDivider)

    let reviewTitle = NSTextField(labelWithString: "Review Mode")
    reviewTitle.font = .boldSystemFont(ofSize: NSFont.systemFontSize)
    reviewTitle.frame = NSRect(x: horizontalInset, y: 546, width: contentWidth, height: 20)
    reviewTitle.autoresizingMask = [.width, .minYMargin]
    contentView.addSubview(reviewTitle)

    reviewModePopUp.addItems(withTitles: [
      reviewModeTitle(for: .publish), reviewModeTitle(for: .pending),
    ])
    reviewModePopUp.target = self
    reviewModePopUp.action = #selector(reviewModeChanged(_:))
    reviewModePopUp.frame = NSRect(x: horizontalInset, y: 510, width: contentWidth, height: 28)
    reviewModePopUp.autoresizingMask = [.width, .minYMargin]
    contentView.addSubview(reviewModePopUp)

    let reviewDivider = NSBox(
      frame: NSRect(x: horizontalInset, y: 482, width: contentWidth, height: 1))
    reviewDivider.boxType = .separator
    reviewDivider.autoresizingMask = [.width, .minYMargin]
    contentView.addSubview(reviewDivider)

    sourcePicker.target = self
    sourcePicker.action = #selector(sourcePickerChanged(_:))
    sourcePicker.selectedSegment = 0
    sourcePicker.segmentStyle = .rounded
    sourcePicker.frame = NSRect(x: horizontalInset, y: 446, width: contentWidth, height: 28)
    sourcePicker.autoresizingMask = [.width, .minYMargin]
    contentView.addSubview(sourcePicker)

    searchField.delegate = self
    searchField.placeholderString = "Search repositories"
    searchField.sendsSearchStringImmediately = true
    searchField.frame = NSRect(x: horizontalInset, y: 410, width: contentWidth, height: 26)
    searchField.autoresizingMask = [.width, .minYMargin]
    contentView.addSubview(searchField)

    listHint.textColor = .secondaryLabelColor
    listHint.frame = NSRect(x: horizontalInset, y: 386, width: contentWidth, height: 18)
    listHint.autoresizingMask = [.width, .minYMargin]
    contentView.addSubview(listHint)

    configureProgressIndicator(listProgressIndicator, x: horizontalInset, y: 386)
    listProgressIndicator.autoresizingMask = [.minYMargin]
    contentView.addSubview(listProgressIndicator)

    scrollView.frame = NSRect(x: horizontalInset, y: 54, width: contentWidth, height: 324)
    scrollView.hasVerticalScroller = true
    scrollView.borderType = .bezelBorder
    scrollView.autoresizingMask = [.width, .height]
    contentView.addSubview(scrollView)

    let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("selection-column"))
    column.width = 440
    tableView.addTableColumn(column)
    tableView.headerView = nil
    tableView.rowHeight = 26
    tableView.intercellSpacing = NSSize(width: 0, height: 2)
    tableView.usesAlternatingRowBackgroundColors = false
    tableView.selectionHighlightStyle = .none
    tableView.focusRingType = .none
    tableView.delegate = self
    tableView.dataSource = self
    scrollView.documentView = tableView

    cancelButton.target = self
    cancelButton.action = #selector(cancel(_:))
    cancelButton.bezelStyle = .rounded
    cancelButton.frame = NSRect(x: 300, y: 12, width: 80, height: 30)
    cancelButton.autoresizingMask = [.minXMargin, .maxYMargin]
    contentView.addSubview(cancelButton)

    saveButton.target = self
    saveButton.action = #selector(save(_:))
    saveButton.bezelStyle = .rounded
    saveButton.frame = NSRect(x: 392, y: 12, width: 88, height: 30)
    saveButton.keyEquivalent = "\r"
    saveButton.autoresizingMask = [.minXMargin, .maxYMargin]
    contentView.addSubview(saveButton)
  }

  private func configureProgressIndicator(_ indicator: NSProgressIndicator, x: CGFloat, y: CGFloat)
  {
    indicator.style = .spinning
    indicator.controlSize = .small
    indicator.isDisplayedWhenStopped = false
    indicator.frame = NSRect(x: x, y: y, width: 16, height: 16)
  }

  private var activeQuery: String {
    switch activeListKind {
    case .repos:
      repoSearchQuery
    case .projects:
      projectSearchQuery
    }
  }

  private var currentRowCount: Int {
    switch activeListKind {
    case .repos:
      filteredRepos.count
    case .projects:
      filteredProjects.count
    }
  }

  private func updateListChrome() {
    searchField.stringValue = activeQuery
    searchField.placeholderString =
      activeListKind == .repos ? "Search repositories" : "Search projects"

    let isLoading: Bool
    let loadingText: String
    let defaultText: String

    switch activeListKind {
    case .repos:
      isLoading = !reposLoaded
      loadingText = "Loading GitHub repositories…"
      defaultText = "Leave all unchecked to include every available repo."
    case .projects:
      isLoading = !projectsLoaded
      loadingText = "Loading Jira projects…"
      defaultText = "Leave all unchecked to include every available project."
    }

    listHint.stringValue = isLoading ? loadingText : defaultText
    listHint.frame = NSRect(
      x: isLoading ? horizontalInset + 24 : horizontalInset,
      y: 386,
      width: isLoading ? contentWidth - 24 : contentWidth,
      height: 18
    )
    listProgressIndicator.isHidden = !isLoading
    if isLoading {
      listProgressIndicator.startAnimation(nil)
    } else {
      listProgressIndicator.stopAnimation(nil)
    }
  }

  private func updateSaveButtonState() {
    saveButton.isEnabled = configLoaded && reposLoaded && projectsLoaded
  }

  private func applyReposSearchFilter() {
    let query = repoSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !query.isEmpty else {
      filteredRepos = repos
      return
    }

    let normalizedQuery = query.lowercased()
    filteredRepos = repos.filter { repo in
      repo.lowercased().contains(normalizedQuery)
    }
  }

  private func applyProjectsSearchFilter() {
    let query = projectSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !query.isEmpty else {
      filteredProjects = projects
      return
    }

    let normalizedQuery = query.lowercased()
    filteredProjects = projects.filter { project in
      project.key.lowercased().contains(normalizedQuery)
        || String(project.id).contains(normalizedQuery)
    }
  }

  private func reviewModeTitle(for mode: CodexCoreCLIClient.ReviewMode) -> String {
    switch mode {
    case .publish:
      "Publish"
    case .pending:
      "Pending"
    }
  }

  private func emptyStateView() -> NSView? {
    let message: String?
    switch activeListKind {
    case .repos:
      if !reposLoaded {
        message = "Loading GitHub repositories..."
      } else if let reposLoadErrorMessage {
        message = reposLoadErrorMessage
      } else if repos.isEmpty {
        message = "No GitHub repositories available for this account."
      } else if filteredRepos.isEmpty {
        message = "No GitHub repositories match your search."
      } else {
        message = nil
      }
    case .projects:
      if !projectsLoaded {
        message = "Loading Jira projects..."
      } else if let projectsLoadErrorMessage {
        message = projectsLoadErrorMessage
      } else if projects.isEmpty {
        message = "No Jira projects available for this account."
      } else if filteredProjects.isEmpty {
        message = "No Jira projects match your search."
      } else {
        message = nil
      }
    }

    guard let message else {
      return nil
    }

    let label = NSTextField(labelWithString: message)
    label.textColor = .secondaryLabelColor
    return label
  }

  private func makeSelectionCellView(identifier: String) -> NSTableCellView {
    let cellView = NSTableCellView(frame: NSRect(x: 0, y: 0, width: 440, height: 24))
    cellView.identifier = NSUserInterfaceItemIdentifier(identifier)

    let button = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    button.frame = NSRect(x: 4, y: 1, width: 432, height: 22)
    button.setButtonType(.switch)
    cellView.addSubview(button)
    return cellView
  }
}
