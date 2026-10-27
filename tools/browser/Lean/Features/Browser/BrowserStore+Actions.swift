import AppKit
import WebKit

extension BrowserStore {
    func findInPage(backwards: Bool = false) {
        findsPage = true
        let config = WKFindConfiguration()
        config.backwards = backwards
        config.wraps = true
        activePage?.webView.find(findText, configuration: config) { _ in }
    }

    func adjacentTab(_ delta: Int) {
        let tabs = sidebarOrder
        guard !tabs.isEmpty else { return }
        let index = tabs.firstIndex { $0.id == selectedTab?.id } ?? 0
        selectTab(tabs[(index + delta + tabs.count) % tabs.count].id)
    }

    func adjacentSpace(_ delta: Int) {
        guard let index = session.spaces.firstIndex(where: { $0.id == activeSpace.id }) else { return }
        selectSpace(session.spaces[(index + delta + session.spaces.count) % session.spaces.count].id)
    }

    func focusSplit(_ delta: Int) {
        guard let split = activeSplit, let index = split.tabIDs.firstIndex(of: selectedTab?.id ?? UUID()) else {
            return
        }
        selectTab(split.tabIDs[(index + delta + split.tabIDs.count) % split.tabIDs.count])
    }

    func moveSplitCard(_ delta: Int) {
        guard let split = activeSplit, let index = split.tabIDs.firstIndex(of: selectedTab?.id ?? UUID()),
            let position = activeSpace.splits.firstIndex(where: { $0.id == split.id }),
            split.tabIDs.indices.contains(index + delta)
        else { return }
        let s = spaceIndex(activeSpace.id)
        session.spaces[s].splits[position].tabIDs.swapAt(index, index + delta)
        session.spaces[s].splits[position].fractions.swapAt(index, index + delta)
        changed()
    }

    func copyAddress(markdown: Bool = false) {
        guard let url = activePage?.url ?? selectedTab?.url else { return }
        let text =
            markdown
            ? "[\(selectedTab?.customTitle ?? activePage?.title ?? url.host ?? "Page")](\(url.absoluteString))"
            : url.absoluteString
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    func togglePin() {
        guard let tab = selectedTab else { return }
        placeTabs([tab.id], as: tab.placement == .pinned ? .current : .pinned)
    }

    func reopenClosedTab() {
        if let entry = session.archive.first(where: { $0.spaceID == activeSpace.id }) { restore(entry) }
    }

    func archiveSelected() {
        if let id = selectedTab?.id { requestDeleteTabs([id]) }
    }

    func openFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        guard let window else { return }
        panel.beginSheetModal(for: window) { result in
            guard result == .OK else { return }
            for url in panel.urls { self.open(url) }
        }
    }

    func savePage(pdf: Bool) {
        guard let page = activePage else { return }
        Task {
            do {
                let data: Data
                if pdf {
                    data = try await page.webView.pdf(configuration: WKPDFConfiguration())
                } else {
                    data = try await withCheckedThrowingContinuation { continuation in
                        page.webView.createWebArchiveData { continuation.resume(with: $0) }
                    }
                }
                let panel = NSSavePanel()
                panel.canCreateDirectories = true
                panel.nameFieldStringValue =
                    BrowserDownloadFile.safeFilename(page.title) + (pdf ? ".pdf" : ".webarchive")
                guard let window else { return }
                let result = await withCheckedContinuation { continuation in
                    panel.beginSheetModal(for: window) { continuation.resume(returning: $0) }
                }
                if result == .OK, let url = panel.url { try data.write(to: url, options: .atomic) }
            } catch { showNotice(error.localizedDescription) }
        }
    }

    func printPage() {
        guard let page = activePage, let window else { return }
        let operation = page.webView.printOperation(with: NSPrintInfo.shared)
        operation.showsPrintPanel = true
        operation.showsProgressPanel = true
        operation.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
    }

    func sharePage() {
        guard let url = activePage?.url, let content = window?.contentView else { return }
        NSSharingServicePicker(items: [url]).show(
            relativeTo: NSRect(x: content.bounds.midX, y: content.bounds.midY, width: 1, height: 1), of: content,
            preferredEdge: .minY)
    }
}
