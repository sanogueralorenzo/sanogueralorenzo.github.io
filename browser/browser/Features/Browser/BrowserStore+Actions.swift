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

    func copyAddress() {
        guard let url = activePage?.url ?? selectedTab?.url else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.absoluteString, forType: .string)
    }

    func openFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        guard let window else { return }
        panel.beginSheetModal(for: window) { result in
            guard result == .OK, !self.isClosed,
                self.canChangeTabCount(by: panel.urls.count, in: self.activeSpace.id)
            else { return }
            for url in panel.urls { self.open(url) }
        }
    }

    func exportPDF() {
        guard let page = activePage else { return }
        Task {
            do {
                let data = try await page.webView.pdf(configuration: WKPDFConfiguration())
                let panel = NSSavePanel()
                panel.canCreateDirectories = true
                panel.nameFieldStringValue = BrowserDownloadFile.safeFilename(page.title) + ".pdf"
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
