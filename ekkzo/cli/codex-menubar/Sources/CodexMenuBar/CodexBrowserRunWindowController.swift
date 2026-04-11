import AppKit
import Foundation

enum BrowserRunTarget: Sendable {
  case githubPullRequest(label: String, pullRequestURL: String)
  case jiraTicket(label: String, ticket: String, issueURL: String)

  static func parse(urlString: String) -> BrowserRunTarget? {
    guard let components = URLComponents(string: urlString),
      let host = components.host?.lowercased()
    else {
      return nil
    }

    let pathComponents = components.path.split(separator: "/").map(String.init)
    if host == "github.com",
      pathComponents.count >= 4,
      pathComponents[2] == "pull"
    {
      let owner = pathComponents[0]
      let repo = pathComponents[1]
      let number = pathComponents[3]
      return .githubPullRequest(
        label: "\(owner)/\(repo)#\(number)",
        pullRequestURL: urlString
      )
    }

    if host == "tonal.atlassian.net",
      pathComponents.count >= 2,
      pathComponents[0] == "browse"
    {
      let ticket = pathComponents[1]
      return .jiraTicket(label: ticket, ticket: ticket, issueURL: urlString)
    }

    return nil
  }
}

@MainActor
final class CodexBrowserRunWindowController: NSWindowController, NSWindowDelegate {
  private let titleLabel = NSTextField(labelWithString: "Run From Browser")
  private let subtitleLabel = NSTextField(labelWithString: "")
  private let detailLabel = NSTextField(labelWithString: "")
  private let reviewModeLabel = NSTextField(labelWithString: "Review Mode")
  private let reviewModePopUp = NSPopUpButton()
  private let loadingIndicator = NSProgressIndicator()
  private let cancelButton = NSButton(title: "Cancel", target: nil, action: nil)
  private let reviewButton = NSButton(title: "Run Review", target: nil, action: nil)
  private let spikeButton = NSButton(title: "Spike", target: nil, action: nil)
  private let taskButton = NSButton(title: "Task", target: nil, action: nil)

  private let onRunReview: (String, CodexCoreCLIClient.ReviewMode) -> Void
  private let onRunTask: (String) -> Void
  private let onRunSpike: (String) -> Void
  private let onClose: () -> Void

  private var currentTarget: BrowserRunTarget?

  init(
    onRunReview: @escaping (String, CodexCoreCLIClient.ReviewMode) -> Void,
    onRunTask: @escaping (String) -> Void,
    onRunSpike: @escaping (String) -> Void,
    onClose: @escaping () -> Void
  ) {
    self.onRunReview = onRunReview
    self.onRunTask = onRunTask
    self.onRunSpike = onRunSpike
    self.onClose = onClose

    let panel = NSPanel(
      contentRect: NSRect(x: 0, y: 0, width: 440, height: 210),
      styleMask: [.titled, .closable],
      backing: .buffered,
      defer: false
    )
    panel.title = "Run From Browser"
    panel.isFloatingPanel = true
    panel.level = .floating
    panel.center()
    panel.setFrameAutosaveName("CodexBrowserRunPanel")

    super.init(window: panel)
    panel.delegate = self
    buildUI(in: panel)
    applyLoading(browserName: nil)
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

  func applyLoading(browserName: String?) {
    currentTarget = nil
    titleLabel.stringValue = "Run From Browser"
    subtitleLabel.stringValue =
      browserName.map { "Reading current tab from \($0)..." } ?? "Reading current browser tab..."
    detailLabel.stringValue = "Open a GitHub pull request or Jira ticket in a supported browser."
    detailLabel.textColor = .secondaryLabelColor
    loadingIndicator.startAnimation(nil)
    reviewModeLabel.isHidden = true
    reviewModePopUp.isHidden = true
    reviewButton.isHidden = true
    reviewButton.isEnabled = false
    spikeButton.isHidden = true
    spikeButton.isEnabled = false
    taskButton.isHidden = true
    taskButton.isEnabled = false
  }

  func applyTarget(_ target: BrowserRunTarget, defaultReviewMode: CodexCoreCLIClient.ReviewMode) {
    currentTarget = target
    loadingIndicator.stopAnimation(nil)

    switch target {
    case .githubPullRequest(let label, _):
      titleLabel.stringValue = "GitHub Pull Request"
      subtitleLabel.stringValue = label
      detailLabel.stringValue =
        "Choose whether to publish findings immediately or keep them pending."
      detailLabel.textColor = .secondaryLabelColor
      reviewModeLabel.isHidden = false
      reviewModePopUp.isHidden = false
      reviewModePopUp.selectItem(at: defaultReviewMode == .publish ? 0 : 1)
      reviewButton.isHidden = false
      reviewButton.isEnabled = true
      spikeButton.isHidden = true
      spikeButton.isEnabled = false
      taskButton.isHidden = true
      taskButton.isEnabled = false

    case .jiraTicket(let label, _, _):
      titleLabel.stringValue = "Jira Ticket"
      subtitleLabel.stringValue = label
      detailLabel.stringValue =
        "Task implements the work and opens a draft PR. Spike investigates and comments the outcome back to Jira."
      detailLabel.textColor = .secondaryLabelColor
      reviewModeLabel.isHidden = true
      reviewModePopUp.isHidden = true
      reviewButton.isHidden = true
      reviewButton.isEnabled = false
      spikeButton.isHidden = false
      spikeButton.isEnabled = true
      taskButton.isHidden = false
      taskButton.isEnabled = true
    }
  }

  func applyError(_ message: String) {
    currentTarget = nil
    loadingIndicator.stopAnimation(nil)
    titleLabel.stringValue = "Run From Browser"
    subtitleLabel.stringValue = "Could not read a supported URL"
    detailLabel.stringValue = message
    detailLabel.textColor = .systemRed
    reviewModeLabel.isHidden = true
    reviewModePopUp.isHidden = true
    reviewButton.isHidden = true
    reviewButton.isEnabled = false
    spikeButton.isHidden = true
    spikeButton.isEnabled = false
    taskButton.isHidden = true
    taskButton.isEnabled = false
  }

  func windowWillClose(_ notification: Notification) {
    onClose()
  }

  @objc private func cancel(_ sender: Any?) {
    close()
  }

  @objc private func runReview(_ sender: Any?) {
    guard case .githubPullRequest(_, let pullRequestURL)? = currentTarget else {
      return
    }
    let mode: CodexCoreCLIClient.ReviewMode =
      reviewModePopUp.indexOfSelectedItem == 0 ? .publish : .pending
    close()
    onRunReview(pullRequestURL, mode)
  }

  @objc private func runTask(_ sender: Any?) {
    guard case .jiraTicket(_, let ticket, _)? = currentTarget else {
      return
    }
    close()
    onRunTask(ticket)
  }

  @objc private func runSpike(_ sender: Any?) {
    guard case .jiraTicket(_, let ticket, _)? = currentTarget else {
      return
    }
    close()
    onRunSpike(ticket)
  }

  private func buildUI(in panel: NSPanel) {
    guard let contentView = panel.contentView else {
      return
    }

    titleLabel.font = .boldSystemFont(ofSize: 18)
    titleLabel.frame = NSRect(x: 20, y: 160, width: 400, height: 24)
    contentView.addSubview(titleLabel)

    subtitleLabel.font = .systemFont(ofSize: 13, weight: .medium)
    subtitleLabel.frame = NSRect(x: 20, y: 132, width: 360, height: 18)
    contentView.addSubview(subtitleLabel)

    configureProgressIndicator(loadingIndicator, x: 392, y: 132)
    contentView.addSubview(loadingIndicator)

    detailLabel.lineBreakMode = .byWordWrapping
    detailLabel.maximumNumberOfLines = 3
    detailLabel.frame = NSRect(x: 20, y: 84, width: 400, height: 42)
    contentView.addSubview(detailLabel)

    reviewModeLabel.font = .boldSystemFont(ofSize: NSFont.systemFontSize)
    reviewModeLabel.frame = NSRect(x: 20, y: 54, width: 120, height: 18)
    contentView.addSubview(reviewModeLabel)

    reviewModePopUp.addItems(withTitles: ["Publish", "Pending"])
    reviewModePopUp.frame = NSRect(x: 150, y: 48, width: 120, height: 26)
    contentView.addSubview(reviewModePopUp)

    cancelButton.target = self
    cancelButton.action = #selector(cancel(_:))
    cancelButton.frame = NSRect(x: 170, y: 12, width: 90, height: 30)
    contentView.addSubview(cancelButton)

    reviewButton.target = self
    reviewButton.action = #selector(runReview(_:))
    reviewButton.keyEquivalent = "\r"
    reviewButton.frame = NSRect(x: 266, y: 12, width: 154, height: 30)
    contentView.addSubview(reviewButton)

    spikeButton.target = self
    spikeButton.action = #selector(runSpike(_:))
    spikeButton.frame = NSRect(x: 74, y: 12, width: 90, height: 30)
    contentView.addSubview(spikeButton)

    taskButton.target = self
    taskButton.action = #selector(runTask(_:))
    taskButton.keyEquivalent = "\r"
    taskButton.frame = NSRect(x: 266, y: 12, width: 90, height: 30)
    contentView.addSubview(taskButton)
  }

  private func configureProgressIndicator(_ indicator: NSProgressIndicator, x: CGFloat, y: CGFloat)
  {
    indicator.style = .spinning
    indicator.controlSize = .small
    indicator.isDisplayedWhenStopped = false
    indicator.frame = NSRect(x: x, y: y, width: 16, height: 16)
  }
}
