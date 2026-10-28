import AppKit

extension LeanAppDelegate {
    func installMenu() {
        let bar = NSMenu()
        let app = submenu("Lean", in: bar)
        item("About Lean", in: app, action: #selector(about))
        item("Settings…", in: app, action: #selector(settings), key: ",")
        app.addItem(.separator())
        item("Hide Lean", in: app, action: #selector(NSApplication.hide(_:)), key: "h", target: NSApp)
        item("Quit Lean", in: app, action: #selector(NSApplication.terminate(_:)), key: "q", target: NSApp)
        let file = submenu("File", in: bar)
        item("New Window", in: file, action: #selector(newWindow), key: "n")
        item(
            "New Private Window", in: file, action: #selector(newPrivateWindow), key: "n",
            modifiers: [.command, .shift])
        item("Import Browser Data…", in: file, action: #selector(importData))
        item("Export Browser Data…", in: file, action: #selector(exportData))
        item("New Tab", in: file, action: #selector(newTab), key: "t")
        item("Open Location…", in: file, action: #selector(openLocation), key: "l")
        item("Close Tab", in: file, action: #selector(closeTab), key: "w")
        item("Close Window", in: file, action: #selector(closeWindow), key: "w", modifiers: [.command, .shift])
        item("Reopen Closed Tab", in: file, action: #selector(reopenTab), key: "t", modifiers: [.command, .shift])
        file.addItem(.separator())
        item("Open File…", in: file, action: #selector(openFile))
        item("Save Web Archive…", in: file, action: #selector(saveArchive))
        item("Export as PDF…", in: file, action: #selector(savePDF))
        item("Print…", in: file, action: #selector(printPage), key: "p")
        item("Share…", in: file, action: #selector(sharePage))
        let edit = submenu("Edit", in: bar)
        item("Undo", in: edit, action: Selector(("undo:")), key: "z", target: nil)
        item("Redo", in: edit, action: Selector(("redo:")), key: "z", modifiers: [.command, .shift], target: nil)
        edit.addItem(.separator())
        item("Cut", in: edit, action: #selector(NSText.cut(_:)), key: "x", target: nil)
        item("Copy", in: edit, action: #selector(NSText.copy(_:)), key: "c", target: nil)
        item("Paste", in: edit, action: #selector(NSText.paste(_:)), key: "v", target: nil)
        item("Select All", in: edit, action: #selector(NSText.selectAll(_:)), key: "a", target: nil)
        item("Find…", in: edit, action: #selector(find), key: "f")
        item("Find Next", in: edit, action: #selector(findNext), key: "g")
        item("Find Previous", in: edit, action: #selector(findPrevious), key: "g", modifiers: [.command, .shift])
        item("Copy Address", in: edit, action: #selector(copyAddress), key: "c", modifiers: [.command, .shift])
        item(
            "Copy Address as Markdown", in: edit, action: #selector(copyMarkdown), key: "c",
            modifiers: [.command, .option, .shift])
        let view = submenu("View", in: bar)
        item("Back", in: view, action: #selector(back), key: "[")
        item("Forward", in: view, action: #selector(forward), key: "]")
        item("Reload", in: view, action: #selector(reload), key: "r")
        item(
            "Reload Without Cache", in: view, action: #selector(reloadFromOrigin), key: "r",
            modifiers: [.command, .shift])
        item("Stop Loading", in: view, action: #selector(stopLoading), key: ".")
        item("Reader Mode", in: view, action: #selector(reader))
        item("Translate Page", in: view, action: #selector(translate), key: "l", modifiers: [.command, .shift])
        item("Developer Tools", in: view, action: #selector(inspector), key: "i", modifiers: [.command, .option])
        view.addItem(.separator())
        item("Split with New Tab", in: view, action: #selector(split))
        item("Pin or Unpin Tab", in: view, action: #selector(pinTab), key: "d")
        item("Archive Tab", in: view, action: #selector(archiveTab), key: "e")
        item(
            "Archive Current Tabs", in: view, action: #selector(archiveCurrent), key: "k",
            modifiers: [.command, .shift])
        item("Change Split Direction", in: view, action: #selector(changeSplit))
        item("Leave Split View", in: view, action: #selector(leaveSplit), key: "u", modifiers: [.command, .option])
        view.addItem(.separator())
        item("Zoom In", in: view, action: #selector(zoomIn), key: "+")
        item("Zoom Out", in: view, action: #selector(zoomOut), key: "-")
        item("Actual Size", in: view, action: #selector(resetZoom), key: "0")
        item("Enter Full Screen", in: view, action: #selector(fullscreen), key: "f", modifiers: [.command, .control])
        let history = submenu("History", in: bar)
        item("Show History", in: history, action: #selector(showHistory), key: "y")
        item("Show Archive", in: history, action: #selector(showArchive))
        item("Show Downloads", in: history, action: #selector(showDownloads), key: "j", modifiers: [.command, .shift])
        NSApp.mainMenu = bar
    }

    private func submenu(_ name: String, in parent: NSMenu) -> NSMenu {
        let item = NSMenuItem(title: name, action: nil, keyEquivalent: "")
        let menu = NSMenu(title: name)
        item.submenu = menu
        parent.addItem(item)
        return menu
    }

    private func item(
        _ title: String, in menu: NSMenu, action: Selector, key: String = "",
        modifiers: NSEvent.ModifierFlags = .command, target: AnyObject? = nil
    ) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        let responderActions = ["cut:", "copy:", "paste:", "selectAll:", "undo:", "redo:"]
        item.target = target ?? (responderActions.contains(NSStringFromSelector(action)) ? nil : self)
        item.keyEquivalentModifierMask = modifiers
        menu.addItem(item)
    }

    @objc private func closeWindow() { window?.performClose(nil) }
    @objc private func reopenTab() { store?.reopenClosedTab() }
    @objc private func openFile() { store?.openFile() }
    @objc private func saveArchive() { store?.savePage(pdf: false) }
    @objc private func savePDF() { store?.savePage(pdf: true) }
    @objc private func printPage() { store?.printPage() }
    @objc private func sharePage() { store?.sharePage() }
    @objc private func copyAddress() { store?.copyAddress() }
    @objc private func copyMarkdown() { store?.copyAddress(markdown: true) }
    @objc private func reloadFromOrigin() { store?.activePage?.webView.reloadFromOrigin() }
    @objc private func stopLoading() { store?.activePage?.webView.stopLoading() }
    @objc private func reader() { store?.activePage?.toggleReader() }
    @objc private func translate() { store?.activePage?.translationRequest &+= 1 }
    @objc private func inspector() { store?.activePage?.showDeveloperTools() }
    @objc private func pinTab() { store?.togglePin() }
    @objc private func archiveTab() { store?.archiveSelected() }
    @objc private func archiveCurrent() { store?.clearCurrentTabs() }
    @objc private func findNext() { store?.findInPage() }
    @objc private func findPrevious() { store?.findInPage(backwards: true) }
    @objc private func newWindow() { createWindow() }
    @objc private func newPrivateWindow() {
        guard let owner else { return }
        do {
            let id = try owner.addSpace(name: "Private", color: 4, isPrivate: true)
            createWindow(restoring: BrowserWindowState(spaceID: id))
        } catch {
            if let store {
                store.showNotice(error.localizedDescription)
            } else {
                let alert = NSAlert()
                alert.messageText = "The private window could not be opened"
                alert.informativeText = error.localizedDescription
                alert.addButton(withTitle: "OK")
                Task { _ = await BrowserDialogs.ask(alert, in: nil) }
            }
        }
    }
    @objc private func importData() { store?.importBrowserData() }
    @objc private func exportData() { store?.exportBrowserData() }
    @objc private func about() { NSApp.orderFrontStandardAboutPanel(nil) }
    @objc private func settings() { store?.openSettings() }
    @objc private func newTab() {
        if store?.addressPresented == true { store?.dismissAddress() } else { store?.presentAddress(newTab: true) }
    }
    @objc private func openLocation() { store?.presentAddress() }
    @objc private func closeTab() {
        if store?.addressPresented == true {
            store?.dismissAddress()
        } else if store?.selectedTab != nil {
            store?.closeSelectedTab()
        } else {
            window?.performClose(nil)
        }
    }
    @objc private func back() { store?.activePage?.webView.goBack() }
    @objc private func forward() { store?.activePage?.webView.goForward() }
    @objc private func reload() { store?.activePage?.webView.reload() }
    @objc private func find() { store?.findsPage = true }
    @objc private func split() { store?.beginSplit() }
    @objc private func changeSplit() { store?.changeSplitDirection() }
    @objc private func leaveSplit() { store?.leaveSplit() }
    @objc private func showHistory() { store?.presentUtility(.history) }
    @objc private func showArchive() { store?.presentUtility(.archive) }
    @objc private func showDownloads() { store?.presentUtility(.downloads) }
    @objc private func zoomIn() {
        if let web = store?.activePage?.webView {
            web.pageZoom = CGFloat(BrowserPageZoom.step(Double(web.pageZoom), increasing: true))
        }
    }
    @objc private func zoomOut() {
        if let web = store?.activePage?.webView {
            web.pageZoom = CGFloat(BrowserPageZoom.step(Double(web.pageZoom), increasing: false))
        }
    }
    @objc private func resetZoom() {
        store?.activePage?.webView.pageZoom = CGFloat(store?.preferences.defaultPageZoom ?? 1)
    }
    @objc private func fullscreen() { window?.toggleFullScreen(nil) }
}
