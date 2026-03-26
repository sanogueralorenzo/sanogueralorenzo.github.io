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

@MainActor
final class CodexAgentSettingsWindowController: NSWindowController, NSWindowDelegate {
  private let ghStatusRow = IntegrationStatusRowView(toolName: "gh")
  private let acliStatusRow = IntegrationStatusRowView(toolName: "acli")
  private let closeButton = NSButton(title: "Close", target: nil, action: nil)
  private let onClose: () -> Void

  init(onClose: @escaping () -> Void) {
    self.onClose = onClose

    let panel = NSPanel(
      contentRect: NSRect(x: 0, y: 0, width: 500, height: 220),
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
    ghStatusRow.apply(status: IntegrationStatus(toolName: "gh", state: .checking))
    acliStatusRow.apply(status: IntegrationStatus(toolName: "acli", state: .checking))
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

  func windowWillClose(_ notification: Notification) {
    onClose()
  }

  @objc private func closePanel(_ sender: Any?) {
    close()
  }

  private func buildUI(in panel: NSPanel) {
    guard let contentView = panel.contentView else {
      return
    }

    let integrationsTitle = NSTextField(labelWithString: "Integrations")
    integrationsTitle.font = .boldSystemFont(ofSize: NSFont.systemFontSize)
    integrationsTitle.frame = NSRect(x: 20, y: 168, width: 460, height: 20)
    contentView.addSubview(integrationsTitle)

    ghStatusRow.frame = NSRect(x: 20, y: 116, width: 460, height: 38)
    contentView.addSubview(ghStatusRow)

    acliStatusRow.frame = NSRect(x: 20, y: 70, width: 460, height: 38)
    contentView.addSubview(acliStatusRow)

    let divider = NSBox(frame: NSRect(x: 20, y: 50, width: 460, height: 1))
    divider.boxType = .separator
    contentView.addSubview(divider)

    closeButton.target = self
    closeButton.action = #selector(closePanel(_:))
    closeButton.keyEquivalent = "\r"
    closeButton.frame = NSRect(x: 392, y: 12, width: 88, height: 30)
    contentView.addSubview(closeButton)
  }
}
