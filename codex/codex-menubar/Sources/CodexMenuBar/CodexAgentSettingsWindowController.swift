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
  let allowedBoardIDs: [Int]
}

@MainActor
final class CodexAgentSettingsWindowController: NSWindowController, NSTableViewDataSource,
  NSTableViewDelegate, NSWindowDelegate, NSSearchFieldDelegate
{
  private enum ListKind {
    case repos
    case boards
  }

  private let ghStatusRow = IntegrationStatusRowView(toolName: "gh")
  private let acliStatusRow = IntegrationStatusRowView(toolName: "acli")
  private let reposProgressIndicator = NSProgressIndicator()
  private let boardsProgressIndicator = NSProgressIndicator()
  private let cancelButton = NSButton(title: "Cancel", target: nil, action: nil)
  private let saveButton = NSButton(title: "Save", target: nil, action: nil)
  private let reviewModePopUp = NSPopUpButton()
  private let reposSearchField = NSSearchField()
  private let boardsSearchField = NSSearchField()
  private let reposTableView = NSTableView()
  private let reposScrollView = NSScrollView()
  private let boardsTableView = NSTableView()
  private let boardsScrollView = NSScrollView()
  private let reposHint = NSTextField(
    labelWithString: "Leave all unchecked to include every available repo.")
  private let boardsHint = NSTextField(
    labelWithString: "Leave all unchecked to include every available board.")

  private let onSave: (CodexAgentSettingsSelection) -> Void
  private let onClose: () -> Void

  private var repos: [String] = []
  private var filteredRepos: [String] = []
  private var selectedRepos: Set<String> = []
  private var boards: [CodexCoreCLIClient.AvailableBoard] = []
  private var filteredBoards: [CodexCoreCLIClient.AvailableBoard] = []
  private var selectedBoardIDs: Set<Int> = []
  private var selectedReviewMode: CodexCoreCLIClient.ReviewMode = .publish
  private var configLoaded = false
  private var reposLoaded = false
  private var boardsLoaded = false
  private var reposLoadErrorMessage: String?
  private var boardsLoadErrorMessage: String?
  private let horizontalInset: CGFloat = 20
  private let contentWidth: CGFloat = 460

  init(onSave: @escaping (CodexAgentSettingsSelection) -> Void, onClose: @escaping () -> Void) {
    self.onSave = onSave
    self.onClose = onClose

    let panel = NSPanel(
      contentRect: NSRect(x: 0, y: 0, width: 500, height: 760),
      styleMask: [.titled, .closable],
      backing: .buffered,
      defer: false
    )
    panel.title = "Agents Settings"
    panel.isFloatingPanel = true
    panel.center()
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
    boardsLoaded = false
    reposLoadErrorMessage = nil
    boardsLoadErrorMessage = nil
    saveButton.isEnabled = false
    selectedReviewMode = .publish
    reviewModePopUp.selectItem(at: 0)
    setListLoadingAppearance(kind: .repos, isLoading: true)
    setListLoadingAppearance(kind: .boards, isLoading: true)
    ghStatusRow.apply(status: IntegrationStatus(toolName: "gh", state: .checking))
    acliStatusRow.apply(status: IntegrationStatus(toolName: "acli", state: .checking))
    applyReposSearchFilter()
    applyBoardsSearchFilter()
    reposTableView.reloadData()
    boardsTableView.reloadData()
  }

  func applyCurrentConfig(_ currentConfig: CodexCoreCLIClient.AgentsConfig) {
    configLoaded = true
    selectedReviewMode = currentConfig.reviewMode
    reviewModePopUp.selectItem(withTitle: reviewModeTitle(for: currentConfig.reviewMode))
    selectedRepos = Set(currentConfig.allowedRepos)
    selectedBoardIDs = Set(currentConfig.allowedBoards)
    updateSaveButtonState()
  }

  func applyAvailableRepos(_ availableRepos: [CodexCoreCLIClient.AvailableRepo]) {
    reposLoaded = true
    reposLoadErrorMessage = nil
    repos = availableRepos.map(\.fullName)
    applyReposSearchFilter()
    setListLoadingAppearance(kind: .repos, isLoading: false)
    updateSaveButtonState()
    reposTableView.reloadData()
  }

  func applyAvailableBoards(_ availableBoards: [CodexCoreCLIClient.AvailableBoard]) {
    boardsLoaded = true
    boardsLoadErrorMessage = nil
    boards = availableBoards
    applyBoardsSearchFilter()
    setListLoadingAppearance(kind: .boards, isLoading: false)
    updateSaveButtonState()
    boardsTableView.reloadData()
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
    boardsLoadErrorMessage = message
    reposLoaded = false
    boardsLoaded = false
    repos = []
    boards = []
    filteredRepos = []
    filteredBoards = []
    saveButton.isEnabled = false
    setListLoadingAppearance(kind: .repos, isLoading: false)
    setListLoadingAppearance(kind: .boards, isLoading: false)
    reposTableView.reloadData()
    boardsTableView.reloadData()
  }

  @objc func save(_ sender: Any?) {
    guard configLoaded && reposLoaded && boardsLoaded else {
      return
    }
    onSave(
      CodexAgentSettingsSelection(
        reviewMode: selectedReviewMode,
        allowedRepos: selectedRepos.sorted(),
        allowedBoardIDs: selectedBoardIDs.sorted()
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
    if tableView === reposTableView {
      return max(filteredRepos.count, 1)
    }
    return max(filteredBoards.count, 1)
  }

  func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView?
  {
    if tableView === reposTableView {
      if let emptyStateView = reposEmptyStateView() {
        return emptyStateView
      }

      let repo = filteredRepos[row]
      let cellView =
        tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier("repo-cell"), owner: self)
        as? NSTableCellView ?? makeSelectionCellView(identifier: "repo-cell")
      let button = cellView.subviews.compactMap({ $0 as? NSButton }).first!
      button.target = self
      button.action = #selector(toggleRepoSelection(_:))
      button.state = selectedRepos.contains(repo) ? .on : .off
      button.identifier = NSUserInterfaceItemIdentifier(rawValue: repo)
      button.title = repo
      return cellView
    }

    if let emptyStateView = boardsEmptyStateView() {
      return emptyStateView
    }

    let board = filteredBoards[row]
    let cellView =
      tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier("board-cell"), owner: self)
      as? NSTableCellView ?? makeSelectionCellView(identifier: "board-cell")
    let button = cellView.subviews.compactMap({ $0 as? NSButton }).first!
    button.target = self
    button.action = #selector(toggleBoardSelection(_:))
    button.state = selectedBoardIDs.contains(board.id) ? .on : .off
    button.identifier = NSUserInterfaceItemIdentifier(rawValue: String(board.id))
    button.title = board.displayName
    return cellView
  }

  func controlTextDidChange(_ obj: Notification) {
    if obj.object as AnyObject? === boardsSearchField {
      applyBoardsSearchFilter()
      boardsTableView.reloadData()
    } else {
      applyReposSearchFilter()
      reposTableView.reloadData()
    }
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

  @objc private func toggleBoardSelection(_ sender: NSButton) {
    guard let identifier = sender.identifier?.rawValue, let boardID = Int(identifier) else {
      return
    }
    if sender.state == .on {
      selectedBoardIDs.insert(boardID)
    } else {
      selectedBoardIDs.remove(boardID)
    }
  }

  @objc private func reviewModeChanged(_ sender: NSPopUpButton) {
    selectedReviewMode = sender.indexOfSelectedItem == 1 ? .pending : .publish
  }

  private func buildUI(in panel: NSPanel) {
    guard let contentView = panel.contentView else {
      return
    }

    let integrationsTitle = NSTextField(labelWithString: "Integrations")
    integrationsTitle.font = .boldSystemFont(ofSize: NSFont.systemFontSize)
    integrationsTitle.frame = NSRect(x: horizontalInset, y: 700, width: contentWidth, height: 20)
    contentView.addSubview(integrationsTitle)

    ghStatusRow.frame = NSRect(x: horizontalInset, y: 650, width: contentWidth, height: 38)
    contentView.addSubview(ghStatusRow)

    acliStatusRow.frame = NSRect(x: horizontalInset, y: 604, width: contentWidth, height: 38)
    contentView.addSubview(acliStatusRow)

    let integrationsDivider = NSBox(
      frame: NSRect(x: horizontalInset, y: 578, width: contentWidth, height: 1))
    integrationsDivider.boxType = .separator
    contentView.addSubview(integrationsDivider)

    let reviewTitle = NSTextField(labelWithString: "Review Mode")
    reviewTitle.font = .boldSystemFont(ofSize: NSFont.systemFontSize)
    reviewTitle.frame = NSRect(x: horizontalInset, y: 546, width: contentWidth, height: 20)
    contentView.addSubview(reviewTitle)

    reviewModePopUp.addItems(withTitles: [
      reviewModeTitle(for: .publish),
      reviewModeTitle(for: .pending),
    ])
    reviewModePopUp.target = self
    reviewModePopUp.action = #selector(reviewModeChanged(_:))
    reviewModePopUp.frame = NSRect(x: horizontalInset, y: 510, width: contentWidth, height: 28)
    contentView.addSubview(reviewModePopUp)

    let reviewDivider = NSBox(
      frame: NSRect(x: horizontalInset, y: 482, width: contentWidth, height: 1))
    reviewDivider.boxType = .separator
    contentView.addSubview(reviewDivider)

    let reposTitle = NSTextField(labelWithString: "GitHub Repositories")
    reposTitle.font = .boldSystemFont(ofSize: NSFont.systemFontSize)
    reposTitle.frame = NSRect(x: horizontalInset, y: 450, width: contentWidth, height: 20)
    contentView.addSubview(reposTitle)

    reposSearchField.delegate = self
    reposSearchField.placeholderString = "Search repositories"
    reposSearchField.sendsSearchStringImmediately = true
    reposSearchField.frame = NSRect(x: horizontalInset, y: 416, width: contentWidth, height: 26)
    contentView.addSubview(reposSearchField)

    reposHint.textColor = .secondaryLabelColor
    reposHint.frame = NSRect(x: horizontalInset, y: 392, width: contentWidth, height: 18)
    contentView.addSubview(reposHint)

    configureProgressIndicator(reposProgressIndicator, x: horizontalInset, y: 392)
    contentView.addSubview(reposProgressIndicator)

    configureSelectionTable(reposTableView, in: reposScrollView, y: 240, height: 144)
    contentView.addSubview(reposScrollView)

    let boardsDivider = NSBox(
      frame: NSRect(x: horizontalInset, y: 220, width: contentWidth, height: 1))
    boardsDivider.boxType = .separator
    contentView.addSubview(boardsDivider)

    let boardsTitle = NSTextField(labelWithString: "Jira Boards")
    boardsTitle.font = .boldSystemFont(ofSize: NSFont.systemFontSize)
    boardsTitle.frame = NSRect(x: horizontalInset, y: 188, width: contentWidth, height: 20)
    contentView.addSubview(boardsTitle)

    boardsSearchField.delegate = self
    boardsSearchField.placeholderString = "Search boards"
    boardsSearchField.sendsSearchStringImmediately = true
    boardsSearchField.frame = NSRect(x: horizontalInset, y: 154, width: contentWidth, height: 26)
    contentView.addSubview(boardsSearchField)

    boardsHint.textColor = .secondaryLabelColor
    boardsHint.frame = NSRect(x: horizontalInset, y: 130, width: contentWidth, height: 18)
    contentView.addSubview(boardsHint)

    configureProgressIndicator(boardsProgressIndicator, x: horizontalInset, y: 130)
    contentView.addSubview(boardsProgressIndicator)

    configureSelectionTable(boardsTableView, in: boardsScrollView, y: 54, height: 68)
    contentView.addSubview(boardsScrollView)

    cancelButton.target = self
    cancelButton.action = #selector(cancel(_:))
    cancelButton.bezelStyle = .rounded
    cancelButton.frame = NSRect(x: 300, y: 12, width: 80, height: 30)
    contentView.addSubview(cancelButton)

    saveButton.target = self
    saveButton.action = #selector(save(_:))
    saveButton.bezelStyle = .rounded
    saveButton.frame = NSRect(x: 392, y: 12, width: 88, height: 30)
    saveButton.keyEquivalent = "\r"
    contentView.addSubview(saveButton)
  }

  private func configureSelectionTable(
    _ tableView: NSTableView,
    in scrollView: NSScrollView,
    y: CGFloat,
    height: CGFloat
  ) {
    scrollView.frame = NSRect(x: horizontalInset, y: y, width: contentWidth, height: height)
    scrollView.hasVerticalScroller = true
    scrollView.borderType = .bezelBorder

    let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(UUID().uuidString))
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
  }

  private func configureProgressIndicator(_ indicator: NSProgressIndicator, x: CGFloat, y: CGFloat)
  {
    indicator.style = .spinning
    indicator.controlSize = .small
    indicator.isDisplayedWhenStopped = false
    indicator.frame = NSRect(x: x, y: y, width: 16, height: 16)
  }

  private func setListLoadingAppearance(kind: ListKind, isLoading: Bool) {
    let hint = kind == .repos ? reposHint : boardsHint
    let indicator = kind == .repos ? reposProgressIndicator : boardsProgressIndicator
    let loadingText =
      kind == .repos ? "Loading GitHub repositories…" : "Loading Jira boards…"
    let defaultText =
      kind == .repos
      ? "Leave all unchecked to include every available repo."
      : "Leave all unchecked to include every available board."
    let hintX = isLoading ? horizontalInset + 24 : horizontalInset
    let hintWidth = isLoading ? contentWidth - 24 : contentWidth

    hint.stringValue = isLoading ? loadingText : defaultText
    hint.frame = NSRect(x: hintX, y: hint.frame.origin.y, width: hintWidth, height: 18)
    indicator.isHidden = !isLoading
    if isLoading {
      indicator.startAnimation(nil)
    } else {
      indicator.stopAnimation(nil)
    }
  }

  private func updateSaveButtonState() {
    saveButton.isEnabled = configLoaded && reposLoaded && boardsLoaded
  }

  private func applyReposSearchFilter() {
    let query = reposSearchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !query.isEmpty else {
      filteredRepos = repos
      return
    }

    let normalizedQuery = query.lowercased()
    filteredRepos = repos.filter { repo in
      repo.lowercased().contains(normalizedQuery)
    }
  }

  private func applyBoardsSearchFilter() {
    let query = boardsSearchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !query.isEmpty else {
      filteredBoards = boards
      return
    }

    let normalizedQuery = query.lowercased()
    filteredBoards = boards.filter { board in
      board.key.lowercased().contains(normalizedQuery)
        || String(board.id).contains(normalizedQuery)
    }
  }

  private func reviewModeTitle(for mode: CodexCoreCLIClient.ReviewMode) -> String {
    switch mode {
    case .publish:
      return "Publish"
    case .pending:
      return "Pending"
    }
  }

  private func reposEmptyStateView() -> NSView? {
    let message: String
    if let reposLoadErrorMessage {
      message = reposLoadErrorMessage
    } else if repos.isEmpty {
      message = "No GitHub repositories available for this account."
    } else if filteredRepos.isEmpty {
      message = "No GitHub repositories match your search."
    } else {
      return nil
    }

    let label = NSTextField(labelWithString: message)
    label.textColor = .secondaryLabelColor
    return label
  }

  private func boardsEmptyStateView() -> NSView? {
    let message: String
    if let boardsLoadErrorMessage {
      message = boardsLoadErrorMessage
    } else if boards.isEmpty {
      message = "No Jira boards available for this account."
    } else if filteredBoards.isEmpty {
      message = "No Jira boards match your search."
    } else {
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
