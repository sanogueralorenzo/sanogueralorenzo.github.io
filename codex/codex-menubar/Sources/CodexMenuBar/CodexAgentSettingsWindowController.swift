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
}

@MainActor
final class CodexAgentSettingsWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate, NSWindowDelegate, NSSearchFieldDelegate {
    private let ghStatusRow = IntegrationStatusRowView(toolName: "gh")
    private let acliStatusRow = IntegrationStatusRowView(toolName: "acli")
    private let progressIndicator = NSProgressIndicator()
    private let cancelButton = NSButton(title: "Cancel", target: nil, action: nil)
    private let saveButton = NSButton(title: "Save", target: nil, action: nil)
    private let reviewModePopUp = NSPopUpButton()
    private let searchField = NSSearchField()
    private let tableView = NSTableView()
    private let scrollView = NSScrollView()
    private let reposHint = NSTextField(labelWithString: "Leave all unchecked to include every available repo.")
    private let defaultReposHint = "Leave all unchecked to include every available repo."
    private let loadingReposHint = "Loading GitHub repositories…"

    private let onSave: (CodexAgentSettingsSelection) -> Void
    private let onClose: () -> Void

    private var repos: [String] = []
    private var filteredRepos: [String] = []
    private var selectedRepos: Set<String> = []
    private var selectedReviewMode: CodexCoreCLIClient.ReviewMode = .publish
    private var configLoaded = false
    private var reposLoaded = false
    private var loadCompleted = false
    private var reposLoadErrorMessage: String?
    private let horizontalInset: CGFloat = 20
    private let contentWidth: CGFloat = 460
    private let reposHintY: CGFloat = 230

    init(onSave: @escaping (CodexAgentSettingsSelection) -> Void, onClose: @escaping () -> Void) {
        self.onSave = onSave
        self.onClose = onClose

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 600),
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
        loadCompleted = false
        reposLoadErrorMessage = nil
        saveButton.isEnabled = false
        selectedReviewMode = .publish
        reviewModePopUp.selectItem(at: 0)
        reposHint.stringValue = loadingReposHint
        progressIndicator.isHidden = false
        progressIndicator.startAnimation(nil)
        ghStatusRow.apply(status: IntegrationStatus(toolName: "gh", state: .checking))
        acliStatusRow.apply(status: IntegrationStatus(toolName: "acli", state: .checking))
        updateReposHintLayout(isLoading: true)
        applySearchFilter()
        tableView.reloadData()
    }

    func applyCurrentConfig(_ currentConfig: CodexCoreCLIClient.AgentsConfig) {
        configLoaded = true
        selectedReviewMode = currentConfig.reviewMode
        reviewModePopUp.selectItem(withTitle: reviewModeTitle(for: currentConfig.reviewMode))
        selectedRepos = Set(currentConfig.allowedRepos)
    }

    func applyAvailableRepos(_ availableRepos: [CodexCoreCLIClient.AvailableRepo]) {
        reposLoaded = true
        reposLoadErrorMessage = nil
        repos = availableRepos.map(\.fullName)
        applySearchFilter()
        loadCompleted = true
        saveButton.isEnabled = configLoaded
        progressIndicator.stopAnimation(nil)
        progressIndicator.isHidden = true
        reposHint.stringValue = defaultReposHint
        updateReposHintLayout(isLoading: false)
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
        loadCompleted = false
        reposLoaded = false
        reposLoadErrorMessage = message
        repos = []
        filteredRepos = []
        saveButton.isEnabled = false
        progressIndicator.stopAnimation(nil)
        progressIndicator.isHidden = true
        reposHint.stringValue = defaultReposHint
        updateReposHintLayout(isLoading: false)
        tableView.reloadData()
    }

    @objc func save(_ sender: Any?) {
        guard loadCompleted else {
            return
        }
        onSave(
            CodexAgentSettingsSelection(
                reviewMode: selectedReviewMode,
                allowedRepos: selectedRepos.sorted()
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
        if reposLoadErrorMessage != nil {
            return 1
        }
        if !reposLoaded {
            return 0
        }
        return max(filteredRepos.count, 1)
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        if let reposLoadErrorMessage {
            let label = NSTextField(labelWithString: reposLoadErrorMessage)
            label.textColor = .secondaryLabelColor
            return label
        }

        if repos.isEmpty {
            let label = NSTextField(labelWithString: "No GitHub repos available for this account.")
            label.textColor = .secondaryLabelColor
            return label
        }

        if filteredRepos.isEmpty {
            let label = NSTextField(labelWithString: "No GitHub repos match your search.")
            label.textColor = .secondaryLabelColor
            return label
        }

        let repo = filteredRepos[row]
        let identifier = NSUserInterfaceItemIdentifier("repo-cell")
        let cellView = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView ?? makeRepoCellView(identifier: identifier)
        guard let button = cellView.subviews.compactMap({ $0 as? NSButton }).first else {
            return cellView
        }
        button.target = self
        button.action = #selector(toggleRepoSelection(_:))
        button.state = selectedRepos.contains(repo) ? .on : .off
        button.identifier = NSUserInterfaceItemIdentifier(rawValue: repo)
        button.title = repo
        return cellView
    }

    func controlTextDidChange(_ obj: Notification) {
        applySearchFilter()
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

    @objc private func reviewModeChanged(_ sender: NSPopUpButton) {
        selectedReviewMode = sender.indexOfSelectedItem == 1 ? .pending : .publish
    }

    private func buildUI(in panel: NSPanel) {
        guard let contentView = panel.contentView else {
            return
        }

        let integrationsTitle = NSTextField(labelWithString: "Integrations")
        integrationsTitle.font = .boldSystemFont(ofSize: NSFont.systemFontSize)
        integrationsTitle.frame = NSRect(x: horizontalInset, y: 540, width: contentWidth, height: 20)
        contentView.addSubview(integrationsTitle)

        ghStatusRow.frame = NSRect(x: horizontalInset, y: 490, width: contentWidth, height: 38)
        contentView.addSubview(ghStatusRow)

        acliStatusRow.frame = NSRect(x: horizontalInset, y: 444, width: contentWidth, height: 38)
        contentView.addSubview(acliStatusRow)

        let integrationsDivider = NSBox(frame: NSRect(x: horizontalInset, y: 418, width: contentWidth, height: 1))
        integrationsDivider.boxType = .separator
        contentView.addSubview(integrationsDivider)

        let reviewTitle = NSTextField(labelWithString: "Review Mode")
        reviewTitle.font = .boldSystemFont(ofSize: NSFont.systemFontSize)
        reviewTitle.frame = NSRect(x: horizontalInset, y: 386, width: contentWidth, height: 20)
        contentView.addSubview(reviewTitle)

        reviewModePopUp.addItems(withTitles: [
            reviewModeTitle(for: .publish),
            reviewModeTitle(for: .pending)
        ])
        reviewModePopUp.target = self
        reviewModePopUp.action = #selector(reviewModeChanged(_:))
        reviewModePopUp.frame = NSRect(x: horizontalInset, y: 350, width: contentWidth, height: 28)
        contentView.addSubview(reviewModePopUp)

        let reviewDivider = NSBox(frame: NSRect(x: horizontalInset, y: 320, width: contentWidth, height: 1))
        reviewDivider.boxType = .separator
        contentView.addSubview(reviewDivider)

        let reposTitle = NSTextField(labelWithString: "GitHub Repos")
        reposTitle.font = .boldSystemFont(ofSize: NSFont.systemFontSize)
        reposTitle.frame = NSRect(x: horizontalInset, y: 288, width: contentWidth, height: 20)
        contentView.addSubview(reposTitle)

        searchField.delegate = self
        searchField.placeholderString = "Search repositories"
        searchField.sendsSearchStringImmediately = true
        searchField.frame = NSRect(x: horizontalInset, y: 254, width: contentWidth, height: 26)
        contentView.addSubview(searchField)

        reposHint.textColor = .secondaryLabelColor
        reposHint.frame = NSRect(x: horizontalInset, y: reposHintY, width: contentWidth, height: 18)
        contentView.addSubview(reposHint)

        progressIndicator.style = .spinning
        progressIndicator.controlSize = .small
        progressIndicator.isDisplayedWhenStopped = false
        progressIndicator.frame = NSRect(x: horizontalInset, y: reposHintY, width: 16, height: 16)
        contentView.addSubview(progressIndicator)

        scrollView.frame = NSRect(x: horizontalInset, y: 82, width: contentWidth, height: 144)
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("repo"))
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
        contentView.addSubview(scrollView)

        cancelButton.target = self
        cancelButton.action = #selector(cancel(_:))
        cancelButton.bezelStyle = .rounded
        cancelButton.frame = NSRect(x: 300, y: 24, width: 80, height: 30)
        contentView.addSubview(cancelButton)

        saveButton.target = self
        saveButton.action = #selector(save(_:))
        saveButton.bezelStyle = .rounded
        saveButton.frame = NSRect(x: 392, y: 24, width: 88, height: 30)
        saveButton.keyEquivalent = "\r"
        contentView.addSubview(saveButton)
    }

    private func updateReposHintLayout(isLoading: Bool) {
        let hintX = isLoading ? horizontalInset + 24 : horizontalInset
        let hintWidth = isLoading ? contentWidth - 24 : contentWidth
        reposHint.frame = NSRect(x: hintX, y: reposHintY, width: hintWidth, height: 18)
    }

    private func applySearchFilter() {
        let query = searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            filteredRepos = repos
            return
        }

        let normalizedQuery = query.lowercased()
        filteredRepos = repos.filter { repo in
            repo.lowercased().contains(normalizedQuery)
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

    private func makeRepoCellView(identifier: NSUserInterfaceItemIdentifier) -> NSTableCellView {
        let cellView = NSTableCellView(frame: NSRect(x: 0, y: 0, width: 440, height: 24))
        cellView.identifier = identifier

        let button = NSButton(checkboxWithTitle: "", target: self, action: #selector(toggleRepoSelection(_:)))
        button.frame = NSRect(x: 4, y: 1, width: 432, height: 22)
        button.setButtonType(.switch)
        cellView.addSubview(button)
        return cellView
    }
}
