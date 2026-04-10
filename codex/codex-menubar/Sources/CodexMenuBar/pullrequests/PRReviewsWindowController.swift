import AppKit
import Foundation

private enum PRReviewsColors {
  static let chromeBorder = NSColor.separatorColor
  static let divider = NSColor.separatorColor
  static let rowBackground = NSColor.clear
  static let pillBackground = NSColor.quaternaryLabelColor.withAlphaComponent(0.24)
  static let statusPillBackground = NSColor.controlBackgroundColor
  static let statusPillPressedBackground = NSColor.selectedContentBackgroundColor
  static let pillSelected = NSColor.controlAccentColor
  static let blueButton = NSColor.controlAccentColor
  static let blueButtonPressed = NSColor.selectedContentBackgroundColor
  static let primaryText = NSColor.labelColor
  static let secondaryText = NSColor.secondaryLabelColor
}

private enum PRReviewsPanelMode {
  case list
  case settings
}

private final class PanelCardView: NSVisualEffectView {
  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
    layer?.cornerRadius = 16
    layer?.masksToBounds = true
    layer?.borderWidth = 1
    layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.45).cgColor
    blendingMode = .behindWindow
    material = .hudWindow
    state = .followsWindowActiveState
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

private final class HeaderIconButton: NSButton {
  init(systemName: String, action: Selector, target: AnyObject?) {
    super.init(frame: .zero)
    bezelStyle = .regularSquare
    isBordered = false
    image = NSImage(systemSymbolName: systemName, accessibilityDescription: nil)
    imagePosition = .imageOnly
    contentTintColor = PRReviewsColors.primaryText
    self.target = target
    self.action = action
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

private final class BackButton: NSButton {
  init(target: AnyObject?, action: Selector) {
    super.init(frame: .zero)
    bezelStyle = .regularSquare
    isBordered = false
    image = NSImage(systemSymbolName: "chevron.left", accessibilityDescription: nil)
    imagePosition = .imageOnly
    contentTintColor = PRReviewsColors.primaryText
    self.target = target
    self.action = action
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

private final class PrimaryActionButton: NSButton {
  override var isEnabled: Bool { didSet { needsDisplay = true } }
  override var isHighlighted: Bool { didSet { needsDisplay = true } }

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    isBordered = false
    bezelStyle = .regularSquare
    font = .systemFont(ofSize: 11, weight: .semibold)
    contentTintColor = .white
  }

  convenience init(title: String, target: AnyObject?, action: Selector) {
    self.init(frame: .zero)
    self.title = title
    self.target = target
    self.action = action
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override func draw(_ dirtyRect: NSRect) {
    let color: NSColor
    if !isEnabled {
      color = PRReviewsColors.pillBackground
    } else if isHighlighted {
      color = PRReviewsColors.blueButtonPressed
    } else {
      color = PRReviewsColors.blueButton
    }

    let path = NSBezierPath(roundedRect: bounds, xRadius: 11, yRadius: 11)
    color.setFill()
    path.fill()

    let attributedTitle = NSAttributedString(
      string: title,
      attributes: [
        .font: font ?? NSFont.systemFont(ofSize: 11, weight: .semibold),
        .foregroundColor: NSColor.white,
      ]
    )
    let size = attributedTitle.size()
    attributedTitle.draw(
      in: NSRect(
        x: (bounds.width - size.width) / 2,
        y: (bounds.height - size.height) / 2 - 1,
        width: size.width,
        height: size.height
      )
    )
  }
}

private final class PRRowView: NSView {
  private let titleLabel = NSTextField(labelWithString: "")
  private let metaLabel = NSTextField(labelWithString: "")
  private let actionButton = PrimaryActionButton(title: "", target: nil, action: #selector(handleAction))
  private let statusLabel = NSTextField(labelWithString: "")
  private let spinner = NSProgressIndicator()
  private let separator = NSBox()
  private var onAction: (() -> Void)?

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)

    titleLabel.font = .boldSystemFont(ofSize: 12)
    titleLabel.textColor = PRReviewsColors.primaryText
    titleLabel.lineBreakMode = .byTruncatingTail
    addSubview(titleLabel)

    metaLabel.font = .systemFont(ofSize: 9, weight: .medium)
    metaLabel.textColor = PRReviewsColors.secondaryText
    metaLabel.lineBreakMode = .byTruncatingTail
    addSubview(metaLabel)

    actionButton.target = self
    addSubview(actionButton)

    statusLabel.font = .systemFont(ofSize: 9, weight: .medium)
    statusLabel.alignment = .right
    statusLabel.textColor = PRReviewsColors.secondaryText
    addSubview(statusLabel)

    spinner.style = .spinning
    spinner.controlSize = .small
    spinner.isDisplayedWhenStopped = false
    addSubview(spinner)

    separator.boxType = .separator
    separator.borderColor = PRReviewsColors.divider
    addSubview(separator)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override func layout() {
    super.layout()
    let content = bounds.insetBy(dx: 10, dy: 6)
    titleLabel.frame = NSRect(x: content.minX, y: content.maxY - 19, width: content.width - 116, height: 16)
    metaLabel.frame = NSRect(x: content.minX, y: content.minY + 1, width: content.width - 116, height: 12)
    actionButton.frame = NSRect(x: content.maxX - 84, y: content.midY - 11, width: 72, height: 22)
    statusLabel.frame = NSRect(x: content.maxX - 156, y: content.minY + 1, width: 60, height: 12)
    spinner.frame = NSRect(x: content.maxX - 28, y: content.midY - 6, width: 12, height: 12)
    separator.frame = NSRect(x: 0, y: 0, width: bounds.width, height: 1)
  }

  func configure(
    pullRequest: PullRequestSummary,
    filter: PRFilter,
    activity: ActivityRecord?,
    canApplyFeedback: Bool,
    onAction: @escaping () -> Void
  ) {
    self.onAction = onAction
    titleLabel.stringValue = pullRequest.title
    metaLabel.stringValue =
      filter == .yours ? "#\(pullRequest.number)   \(pullRequest.headRefName)" : pullRequest.metaLine

    actionButton.title = switch filter {
    case .all: "Review"
    case .yours: "Apply"
    case .reviews: "Open"
    }
    actionButton.isHidden = filter == .yours && !canApplyFeedback
    actionButton.isEnabled = filter != .yours || canApplyFeedback
    spinner.stopAnimation(nil)
    statusLabel.stringValue = ""
    statusLabel.textColor = PRReviewsColors.secondaryText

    if let activity {
      switch activity.status {
      case .running:
        actionButton.isHidden = true
        spinner.startAnimation(nil)
        statusLabel.stringValue = switch filter {
        case .all: "Reviewing"
        case .yours: "Applying"
        case .reviews: ""
        }
      case .completed:
        statusLabel.stringValue = activity.kind == .review ? "Reviewed" : "Applied"
        statusLabel.textColor = .systemGreen
      case .failed:
        statusLabel.stringValue = "Failed"
        statusLabel.textColor = .systemRed
      }
    }
    needsLayout = true
  }

  override func draw(_ dirtyRect: NSRect) {
    super.draw(dirtyRect)
    PRReviewsColors.rowBackground.setFill()
    dirtyRect.fill()
  }

  @objc private func handleAction() { onAction?() }
}

private final class PRTableRowView: NSTableRowView {
  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override func drawSelection(in dirtyRect: NSRect) {}

  override func drawBackground(in dirtyRect: NSRect) {
    PRReviewsColors.rowBackground.setFill()
    dirtyRect.fill()
  }
}

private final class IntegrationStatusPillButton: NSButton {
  private static let horizontalPadding: CGFloat = 10
  private static let dotSize: CGFloat = 6
  private static let gap: CGFloat = 6

  enum DotState {
    case checking
    case connected
    case unavailable

    var color: NSColor {
      switch self {
      case .checking: return .systemGray
      case .connected: return .systemGreen
      case .unavailable: return .systemRed
      }
    }
  }

  private let dotLayer = CALayer()
  private let label = NSTextField(labelWithString: "")
  private var targetURL: URL?

  override var isHighlighted: Bool {
    didSet { needsDisplay = true }
  }

  init(title: String) {
    super.init(frame: .zero)
    wantsLayer = true
    isBordered = false
    bezelStyle = .regularSquare
    label.stringValue = title
    label.font = .systemFont(ofSize: 10, weight: .semibold)
    label.textColor = PRReviewsColors.primaryText
    addSubview(label)

    dotLayer.cornerRadius = 3
    layer?.addSublayer(dotLayer)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  var preferredWidth: CGFloat {
    let labelWidth = ceil(label.attributedStringValue.size().width)
    return Self.horizontalPadding + Self.dotSize + Self.gap + labelWidth + Self.horizontalPadding + 4
  }

  override func layout() {
    super.layout()
    dotLayer.frame = CGRect(
      x: Self.horizontalPadding,
      y: bounds.midY - (Self.dotSize / 2),
      width: Self.dotSize,
      height: Self.dotSize
    )
    let labelX = Self.horizontalPadding + Self.dotSize + Self.gap
    label.frame = NSRect(x: labelX, y: bounds.midY - 7, width: bounds.width - labelX - Self.horizontalPadding, height: 14)
  }

  override func draw(_ dirtyRect: NSRect) {
    let fill = isHighlighted
      ? PRReviewsColors.statusPillPressedBackground
      : PRReviewsColors.statusPillBackground
    let path = NSBezierPath(roundedRect: bounds, xRadius: 11, yRadius: 11)
    fill.setFill()
    path.fill()
    PRReviewsColors.chromeBorder.setStroke()
    path.lineWidth = 1
    path.stroke()
  }

  func apply(status: IntegrationStatus, fallbackURL: URL?) {
    switch status.state {
    case .checking:
      dotLayer.backgroundColor = DotState.checking.color.cgColor
      targetURL = nil
    case .ready:
      dotLayer.backgroundColor = DotState.connected.color.cgColor
      targetURL = nil
    case .actionNeeded, .missing, .error:
      dotLayer.backgroundColor = DotState.unavailable.color.cgColor
      targetURL = fallbackURL
    }
    needsDisplay = true
  }

  @objc func openIfAvailable() {
    guard let targetURL else { return }
    NSWorkspace.shared.open(targetURL)
  }
}

@MainActor
final class PRReviewsViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate, NSSearchFieldDelegate {
  static let preferredSize = NSSize(width: 480, height: 350)
  private static let thresholdFormatter: NumberFormatter = {
    let formatter = NumberFormatter()
    formatter.numberStyle = .none
    formatter.minimum = 0
    formatter.maximum = 99
    formatter.allowsFloats = false
    formatter.isPartialStringValidationEnabled = true
    return formatter
  }()

  private let cardView = PanelCardView()
  private let headerDivider = NSBox()
  private let titleLabel = NSTextField(labelWithString: "PR Reviews")
  private let clearButton: HeaderIconButton
  private let settingsButton: HeaderIconButton
  private let backButton: BackButton

  private let listContentView = NSView()
  private let filterControl = NSSegmentedControl(
    labels: PRFilter.allCases.map(\.title),
    trackingMode: .selectOne,
    target: nil,
    action: nil
  )
  private let listScrollView = NSScrollView()
  private let listTableView = NSTableView()
  private let emptyLabel = NSTextField(labelWithString: "")
  private let loadingIndicator = NSProgressIndicator()

  private let settingsContentView = NSView()
  private let ghPill = IntegrationStatusPillButton(title: "GitHub")
  private let codexPill = IntegrationStatusPillButton(title: "Codex")
  private let settingsStackView = NSStackView()
  private let thresholdLabel = NSTextField(labelWithString: "Apply Threshold")
  private let thresholdInfoButton = NSButton()
  private let thresholdField = NSTextField(string: "0")
  private let reposLabel = NSTextField(labelWithString: "Repositories")
  private let thresholdRowStackView = NSStackView()
  private let thresholdTitleStackView = NSStackView()
  private let repositoriesRowStackView = NSStackView()
  private let searchField = NSSearchField()
  private let settingsTableView = NSTableView()
  private let settingsScrollView = NSScrollView()
  private let settingsEmptyLabel = NSTextField(labelWithString: "")
  private let settingsLoadingIndicator = NSProgressIndicator()

  private let onShowSettings: () -> Void
  private let onClear: () -> Void
  private let onFilterChange: (PRFilter) -> Void
  private let onAction: (PullRequestSummary, PRFilter) -> Void
  private let onSelectionChange: ([String]) -> Void
  private let onThresholdChange: (Int) -> Void

  private var items: [PullRequestSummary] = []
  private var activities: [String: ActivityRecord] = [:]
  private var currentFilter: PRFilter = .all
  private var minimumCommentsForApplyFeedback = 0
  private var panelMode: PRReviewsPanelMode = .list
  private var availableRepos: [AvailableRepo] = []
  private var filteredRepos: [AvailableRepo] = []
  private var selectedRepos = Set<String>()
  private var settingsIsLoading = false
  private lazy var thresholdInfoPopover: NSPopover = {
    let label = NSTextField(
      wrappingLabelWithString: "Ignore auto-comments on PR open so Apply only shows real feedback."
    )
    label.font = .systemFont(ofSize: 11)
    label.textColor = PRReviewsColors.primaryText
    label.maximumNumberOfLines = 0
    label.translatesAutoresizingMaskIntoConstraints = false

    let contentView = NSView(frame: NSRect(x: 0, y: 0, width: 240, height: 64))
    contentView.addSubview(label)
    NSLayoutConstraint.activate([
      label.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
      label.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
      label.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
      label.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12),
      contentView.widthAnchor.constraint(equalToConstant: 240),
    ])

    let controller = NSViewController()
    controller.view = contentView

    let popover = NSPopover()
    popover.behavior = .transient
    popover.animates = true
    popover.contentViewController = controller
    return popover
  }()

  init(
    onShowSettings: @escaping () -> Void,
    onClear: @escaping () -> Void,
    onFilterChange: @escaping (PRFilter) -> Void,
    onAction: @escaping (PullRequestSummary, PRFilter) -> Void,
    onSelectionChange: @escaping ([String]) -> Void,
    onThresholdChange: @escaping (Int) -> Void
  ) {
    self.onShowSettings = onShowSettings
    self.onClear = onClear
    self.onFilterChange = onFilterChange
    self.onAction = onAction
    self.onSelectionChange = onSelectionChange
    self.onThresholdChange = onThresholdChange
    self.clearButton = HeaderIconButton(systemName: "trash", action: #selector(clearFinished(_:)), target: nil)
    self.settingsButton = HeaderIconButton(systemName: "gearshape", action: #selector(openSettings(_:)), target: nil)
    self.backButton = BackButton(target: nil, action: #selector(closeSettings(_:)))
    super.init(nibName: nil, bundle: nil)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override func loadView() {
    view = NSView(frame: NSRect(origin: .zero, size: Self.preferredSize))
    view.wantsLayer = true
    view.layer?.backgroundColor = NSColor.clear.cgColor
    preferredContentSize = Self.preferredSize
    buildUI()
    applyPanelMode(.list)
  }

  override func viewDidLayout() {
    super.viewDidLayout()
    updateTableWidths()
  }

  func applyState(
    filter: PRFilter,
    items: [PullRequestSummary],
    activities: [String: ActivityRecord],
    minimumCommentsForApplyFeedback: Int,
    isLoading: Bool,
    error: String?
  ) {
    currentFilter = filter
    self.items = items
    self.activities = activities
    self.minimumCommentsForApplyFeedback = minimumCommentsForApplyFeedback
    thresholdField.stringValue = String(minimumCommentsForApplyFeedback)
    filterControl.selectedSegment = filter.rawValue
    loadingIndicator.isHidden = !isLoading
    if isLoading {
      loadingIndicator.startAnimation(nil)
    } else {
      loadingIndicator.stopAnimation(nil)
    }

    if let error {
      emptyLabel.stringValue = error
      emptyLabel.textColor = .systemRed
      emptyLabel.isHidden = false
    } else {
      emptyLabel.isHidden = true
    }

    clearButton.isHidden = !activities.values.contains { $0.status != .running }
    listTableView.reloadData()
  }

  func applySettingsState(
    statuses: [IntegrationStatus],
    availableRepos: [AvailableRepo],
    selectedRepos: [String],
    minimumCommentsForApplyFeedback: Int,
    isLoading: Bool
  ) {
    for status in statuses {
      switch status.toolName {
      case "gh":
        ghPill.apply(status: status, fallbackURL: URL(string: "https://cli.github.com/"))
      case "codex":
        codexPill.apply(status: status, fallbackURL: URL(string: "https://developers.openai.com/codex/cli"))
      default: break
      }
    }
    self.availableRepos = availableRepos
    self.selectedRepos = Set(selectedRepos)
    self.minimumCommentsForApplyFeedback = minimumCommentsForApplyFeedback
    settingsIsLoading = isLoading
    thresholdField.stringValue = String(minimumCommentsForApplyFeedback)
    settingsLoadingIndicator.isHidden = !isLoading
    if isLoading {
      settingsLoadingIndicator.startAnimation(nil)
    } else {
      settingsLoadingIndicator.stopAnimation(nil)
    }
    applySettingsFilter()
  }

  func showSettings() {
    applyPanelMode(.settings)
    onShowSettings()
  }

  func resetToMainScreen() {
    thresholdInfoPopover.performClose(nil)
    applyPanelMode(.list)
  }

  func numberOfRows(in tableView: NSTableView) -> Int {
    if tableView === listTableView {
      return items.count
    }
    return filteredRepos.count
  }

  func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
    if tableView === listTableView {
      let item = items[row]
      let rowView = PRRowView(frame: NSRect(x: 0, y: 0, width: listTableView.bounds.width, height: 48))
      let canApplyFeedback = item.commentCount > minimumCommentsForApplyFeedback
      rowView.configure(
        pullRequest: item,
        filter: currentFilter,
        activity: activities[item.url],
        canApplyFeedback: canApplyFeedback
      ) { [weak self] in
        self?.onAction(item, self?.currentFilter ?? .all)
      }
      return rowView
    }

    let repo = filteredRepos[row]
    let button = NSButton(checkboxWithTitle: repo.fullName, target: self, action: #selector(toggleRepo(_:)))
    button.state = selectedRepos.contains(repo.fullName) ? .on : .off
    button.tag = row
    button.font = .systemFont(ofSize: 11)
    button.contentTintColor = PRReviewsColors.primaryText
    return button
  }

  func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
    if tableView === listTableView {
      return 48
    }
    return 22
  }

  func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
    guard tableView === listTableView else { return nil }
    return PRTableRowView()
  }

  func controlTextDidChange(_ notification: Notification) {
    if let field = notification.object as? NSSearchField, field === searchField {
      applySettingsFilter()
    }
  }

  func controlTextDidEndEditing(_ notification: Notification) {
    if let field = notification.object as? NSTextField, field === thresholdField {
      commitThresholdFieldChange()
    }
  }

  @objc private func openSettings(_ sender: Any?) {
    showSettings()
  }

  @objc private func closeSettings(_ sender: Any?) {
    applyPanelMode(.list)
  }

  @objc private func clearFinished(_ sender: Any?) {
    onClear()
  }

  @objc private func toggleRepo(_ sender: NSButton) {
    let repo = filteredRepos[sender.tag].fullName
    if sender.state == .on {
      selectedRepos.insert(repo)
    } else {
      selectedRepos.remove(repo)
    }
    onSelectionChange(selectedRepos.sorted())
  }

  @objc private func toggleThresholdInfo(_ sender: NSButton) {
    if thresholdInfoPopover.isShown {
      thresholdInfoPopover.performClose(sender)
    } else {
      thresholdInfoPopover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .maxY)
    }
  }

  @objc private func commitThresholdFieldChange() {
    let value = min(99, max(0, thresholdField.integerValue))
    let normalized = String(value)
    if thresholdField.stringValue != normalized {
      thresholdField.stringValue = normalized
    }
    guard minimumCommentsForApplyFeedback != value else { return }
    minimumCommentsForApplyFeedback = value
    onThresholdChange(value)
  }

  private func updateTableWidths() {
    let listWidth = listScrollView.contentSize.width
    if let column = listTableView.tableColumns.first, column.width != listWidth {
      column.width = listWidth
    }
    if listTableView.frame.width != listWidth {
      listTableView.frame.size.width = listWidth
    }

    let settingsWidth = settingsScrollView.contentSize.width
    if let column = settingsTableView.tableColumns.first, column.width != settingsWidth {
      column.width = settingsWidth
    }
    if settingsTableView.frame.width != settingsWidth {
      settingsTableView.frame.size.width = settingsWidth
    }
  }

  private func buildUI() {
    cardView.frame = NSRect(x: 0, y: 0, width: 480, height: 350)
    view.addSubview(cardView)

    titleLabel.font = .boldSystemFont(ofSize: 16)
    titleLabel.textColor = PRReviewsColors.primaryText
    titleLabel.frame = NSRect(x: 16, y: 307, width: 110, height: 22)
    cardView.addSubview(titleLabel)

    backButton.target = self
    backButton.frame = NSRect(x: 12, y: 309, width: 20, height: 20)
    cardView.addSubview(backButton)

    clearButton.target = self
    clearButton.frame = NSRect(x: 414, y: 307, width: 22, height: 22)
    cardView.addSubview(clearButton)

    settingsButton.target = self
    settingsButton.frame = NSRect(x: 442, y: 307, width: 22, height: 22)
    cardView.addSubview(settingsButton)

    let pillY: CGFloat = 307
    let pillHeight: CGFloat = 22
    let githubPillWidth = ghPill.preferredWidth
    let codexPillWidth = codexPill.preferredWidth
    let pillGap: CGFloat = 8
    let githubPillX = 464 - githubPillWidth
    let codexPillX = githubPillX - pillGap - codexPillWidth

    ghPill.target = ghPill
    ghPill.action = #selector(IntegrationStatusPillButton.openIfAvailable)
    ghPill.frame = NSRect(x: githubPillX, y: pillY, width: githubPillWidth, height: pillHeight)
    cardView.addSubview(ghPill)

    codexPill.target = codexPill
    codexPill.action = #selector(IntegrationStatusPillButton.openIfAvailable)
    codexPill.frame = NSRect(x: codexPillX, y: pillY, width: codexPillWidth, height: pillHeight)
    cardView.addSubview(codexPill)

    headerDivider.boxType = .separator
    headerDivider.borderColor = PRReviewsColors.divider
    headerDivider.frame = NSRect(x: 0, y: 292, width: 480, height: 1)
    cardView.addSubview(headerDivider)

    buildListContent()
    buildSettingsContent()
  }

  private func buildListContent() {
    listContentView.frame = NSRect(x: 0, y: 0, width: 480, height: 292)
    cardView.addSubview(listContentView)

    filterControl.target = self
    filterControl.action = #selector(changeFilter(_:))
    filterControl.selectedSegment = PRFilter.all.rawValue
    filterControl.segmentStyle = .rounded
    filterControl.setWidth(68, forSegment: PRFilter.all.rawValue)
    filterControl.setWidth(72, forSegment: PRFilter.yours.rawValue)
    filterControl.setWidth(72, forSegment: PRFilter.reviews.rawValue)
    filterControl.frame = NSRect(x: 126, y: 305, width: 228, height: 26)
    cardView.addSubview(filterControl)

    loadingIndicator.style = .spinning
    loadingIndicator.controlSize = .small
    loadingIndicator.translatesAutoresizingMaskIntoConstraints = false
    listContentView.addSubview(loadingIndicator)

    let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("pr"))
    column.width = 480
    column.resizingMask = .autoresizingMask
    listTableView.addTableColumn(column)
    listTableView.headerView = nil
    listTableView.delegate = self
    listTableView.dataSource = self
    listTableView.rowSizeStyle = .custom
    listTableView.selectionHighlightStyle = .none
    listTableView.intercellSpacing = .zero
    listTableView.backgroundColor = .clear
    listTableView.focusRingType = .none
    listTableView.style = .fullWidth
    listTableView.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle
    listTableView.usesAlternatingRowBackgroundColors = false

    listScrollView.frame = NSRect(x: 0, y: 0, width: 480, height: 292)
    listScrollView.borderType = .noBorder
    listScrollView.hasVerticalScroller = true
    listScrollView.scrollerStyle = .overlay
    listScrollView.drawsBackground = false
    listScrollView.contentInsets = NSEdgeInsetsZero
    listScrollView.scrollerInsets = NSEdgeInsetsZero
    listScrollView.documentView = listTableView
    listContentView.addSubview(listScrollView)

    emptyLabel.font = .systemFont(ofSize: 12, weight: .medium)
    emptyLabel.alignment = .center
    emptyLabel.translatesAutoresizingMaskIntoConstraints = false
    listContentView.addSubview(emptyLabel)
    NSLayoutConstraint.activate([
      emptyLabel.centerXAnchor.constraint(equalTo: listContentView.centerXAnchor),
      emptyLabel.centerYAnchor.constraint(equalTo: listContentView.centerYAnchor),
      emptyLabel.widthAnchor.constraint(lessThanOrEqualTo: listContentView.widthAnchor, constant: -32),
      loadingIndicator.centerXAnchor.constraint(equalTo: listContentView.centerXAnchor),
      loadingIndicator.centerYAnchor.constraint(equalTo: listContentView.centerYAnchor),
    ])
  }

  private func buildSettingsContent() {
    settingsContentView.frame = NSRect(x: 0, y: 0, width: 480, height: 292)
    cardView.addSubview(settingsContentView)

    settingsStackView.orientation = .vertical
    settingsStackView.alignment = .leading
    settingsStackView.spacing = 10
    settingsStackView.translatesAutoresizingMaskIntoConstraints = false
    settingsContentView.addSubview(settingsStackView)

    thresholdRowStackView.orientation = .horizontal
    thresholdRowStackView.alignment = .centerY
    thresholdRowStackView.spacing = 8
    thresholdRowStackView.translatesAutoresizingMaskIntoConstraints = false

    thresholdTitleStackView.orientation = .horizontal
    thresholdTitleStackView.alignment = .top
    thresholdTitleStackView.spacing = 4
    thresholdTitleStackView.translatesAutoresizingMaskIntoConstraints = false

    thresholdLabel.font = .boldSystemFont(ofSize: 13)
    thresholdLabel.textColor = PRReviewsColors.primaryText
    thresholdTitleStackView.addArrangedSubview(thresholdLabel)
    thresholdTitleStackView.addArrangedSubview(thresholdInfoButton)
    thresholdRowStackView.addArrangedSubview(thresholdTitleStackView)

    thresholdInfoButton.isBordered = false
    thresholdInfoButton.bezelStyle = .regularSquare
    thresholdInfoButton.image = NSImage(systemSymbolName: "info.circle", accessibilityDescription: "Threshold help")
    thresholdInfoButton.imagePosition = .imageOnly
    thresholdInfoButton.contentTintColor = PRReviewsColors.secondaryText
    thresholdInfoButton.target = self
    thresholdInfoButton.action = #selector(toggleThresholdInfo(_:))
    thresholdInfoButton.translatesAutoresizingMaskIntoConstraints = false
    thresholdInfoButton.imageScaling = .scaleProportionallyDown
    NSLayoutConstraint.activate([
      thresholdInfoButton.widthAnchor.constraint(equalToConstant: 12),
      thresholdInfoButton.heightAnchor.constraint(equalToConstant: 12),
    ])

    thresholdField.font = .monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
    thresholdField.textColor = PRReviewsColors.primaryText
    thresholdField.alignment = .center
    thresholdField.delegate = self
    thresholdField.formatter = Self.thresholdFormatter
    thresholdField.target = self
    thresholdField.action = #selector(commitThresholdFieldChange)
    thresholdField.bezelStyle = .roundedBezel
    thresholdField.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      thresholdField.widthAnchor.constraint(equalToConstant: 40)
    ])
    thresholdRowStackView.addArrangedSubview(thresholdField)

    repositoriesRowStackView.orientation = .horizontal
    repositoriesRowStackView.alignment = .centerY
    repositoriesRowStackView.spacing = 8
    repositoriesRowStackView.translatesAutoresizingMaskIntoConstraints = false

    reposLabel.font = .boldSystemFont(ofSize: 13)
    reposLabel.textColor = PRReviewsColors.primaryText
    repositoriesRowStackView.addArrangedSubview(reposLabel)

    searchField.placeholderString = "Search"
    searchField.delegate = self
    searchField.font = .systemFont(ofSize: 11)
    searchField.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      searchField.widthAnchor.constraint(equalToConstant: 180)
    ])
    repositoriesRowStackView.addArrangedSubview(searchField)

    let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("repo"))
    column.width = 460
    settingsTableView.addTableColumn(column)
    settingsTableView.headerView = nil
    settingsTableView.delegate = self
    settingsTableView.dataSource = self
    settingsTableView.style = .fullWidth
    settingsScrollView.documentView = settingsTableView
    settingsScrollView.drawsBackground = false
    settingsScrollView.borderType = .noBorder
    settingsScrollView.hasVerticalScroller = true
    settingsScrollView.scrollerStyle = .overlay
    settingsScrollView.contentInsets = NSEdgeInsetsZero
    settingsScrollView.scrollerInsets = NSEdgeInsetsZero
    settingsScrollView.translatesAutoresizingMaskIntoConstraints = false
    settingsStackView.addArrangedSubview(thresholdRowStackView)
    settingsStackView.addArrangedSubview(repositoriesRowStackView)
    settingsStackView.addArrangedSubview(settingsScrollView)

    settingsEmptyLabel.font = .systemFont(ofSize: 11)
    settingsEmptyLabel.textColor = PRReviewsColors.secondaryText
    settingsEmptyLabel.alignment = .center
    settingsEmptyLabel.translatesAutoresizingMaskIntoConstraints = false
    settingsContentView.addSubview(settingsEmptyLabel)

    settingsLoadingIndicator.style = .spinning
    settingsLoadingIndicator.controlSize = .small
    settingsLoadingIndicator.translatesAutoresizingMaskIntoConstraints = false
    settingsLoadingIndicator.isDisplayedWhenStopped = false
    settingsContentView.addSubview(settingsLoadingIndicator)

    NSLayoutConstraint.activate([
      settingsStackView.topAnchor.constraint(equalTo: settingsContentView.topAnchor, constant: 10),
      settingsStackView.leadingAnchor.constraint(equalTo: settingsContentView.leadingAnchor, constant: 16),
      settingsStackView.trailingAnchor.constraint(equalTo: settingsContentView.trailingAnchor, constant: -16),
      settingsStackView.bottomAnchor.constraint(equalTo: settingsContentView.bottomAnchor),
      settingsStackView.widthAnchor.constraint(equalTo: settingsContentView.widthAnchor, constant: -32),
      settingsScrollView.widthAnchor.constraint(equalTo: settingsStackView.widthAnchor),
      settingsScrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 160),
      searchField.heightAnchor.constraint(equalToConstant: 24),
      repositoriesRowStackView.widthAnchor.constraint(equalTo: settingsStackView.widthAnchor),
      settingsTableView.widthAnchor.constraint(equalTo: settingsScrollView.widthAnchor),
    ])

    NSLayoutConstraint.activate([
      settingsEmptyLabel.centerXAnchor.constraint(equalTo: settingsScrollView.centerXAnchor),
      settingsEmptyLabel.centerYAnchor.constraint(equalTo: settingsScrollView.centerYAnchor),
      settingsEmptyLabel.widthAnchor.constraint(lessThanOrEqualTo: settingsScrollView.widthAnchor, constant: -32),
      settingsLoadingIndicator.centerXAnchor.constraint(equalTo: settingsScrollView.centerXAnchor),
      settingsLoadingIndicator.centerYAnchor.constraint(equalTo: settingsScrollView.centerYAnchor),
    ])
  }

  private func applyPanelMode(_ mode: PRReviewsPanelMode) {
    panelMode = mode
    switch mode {
    case .list:
      titleLabel.stringValue = "PR Reviews"
      titleLabel.frame = NSRect(x: 16, y: 307, width: 110, height: 22)
      backButton.isHidden = true
      clearButton.isHidden = !activities.values.contains { $0.status != .running }
      settingsButton.isHidden = false
      ghPill.isHidden = true
      codexPill.isHidden = true
      filterControl.isHidden = false
      listContentView.isHidden = false
      settingsContentView.isHidden = true
    case .settings:
      titleLabel.stringValue = "Settings"
      titleLabel.frame = NSRect(x: 38, y: 307, width: 220, height: 22)
      backButton.isHidden = false
      clearButton.isHidden = true
      settingsButton.isHidden = true
      ghPill.isHidden = false
      codexPill.isHidden = false
      filterControl.isHidden = true
      loadingIndicator.isHidden = true
      listContentView.isHidden = true
      settingsContentView.isHidden = false
    }
  }

  private func applySettingsFilter() {
    let query = searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if query.isEmpty {
      filteredRepos = availableRepos
    } else {
      filteredRepos = availableRepos.filter { $0.fullName.lowercased().contains(query) }
    }
    settingsTableView.reloadData()
    settingsEmptyLabel.stringValue = settingsIsLoading ? "" : (filteredRepos.isEmpty ? "No repositories" : "")
  }

  @objc private func changeFilter(_ sender: NSSegmentedControl) {
    guard let filter = PRFilter(rawValue: sender.selectedSegment) else { return }
    onFilterChange(filter)
  }
}
