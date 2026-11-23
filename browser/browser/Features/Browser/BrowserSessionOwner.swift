import AppKit
import Foundation
import Observation
import WebKit

/// Every ordinary window shares this session.
@MainActor @Observable
final class BrowserSessionOwner {
    var session: BrowserSession
    let persistence: BrowserPersistence
    let contentExtension: BrowserContentExtension
    var pages: [UUID: BrowserPage] = [:]
    var profiles: [UUID: WKWebsiteDataStore] = [:]
    var contentBlockers: [UUID: BrowserContentBlocking] = [:]
    var integrations: [UUID: GitHubFolder] = [:]
    var downloads: [ObjectIdentifier: BrowserDownload] = [:]
    var pendingDownloads: [UUID: BrowserPendingDownload] = [:]
    var contexts: [UUID: BrowserStore] = [:]
    var runtimeRevision = 0
    var lastRetentionSweep = Date.distantPast
    var storageError: String?
    var showsRecoveryNotice = false
    var activeWindowID: UUID?
    let sidebarDrag = BrowserSidebarDragSession()
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var savingRevision: UInt64?
    @ObservationIgnored private var maintenance: Task<Void, Never>?
    @ObservationIgnored private var pageMaintenance: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored var openWindow: ((BrowserWindowState?) -> Void)?
    @ObservationIgnored var media: BrowserSystemMedia?

    init() throws {
        persistence = try BrowserPersistence()
        contentExtension = BrowserContentExtension(profile: persistence.directory)
        let saved = try persistence.load()
        session = saved.session
        session.normalizeLiveFolders()
        session.windows.removeAll { !$0.isOpen }
        for index in session.spaces.indices { session.spaces[index].limitPinnedTabs() }
        sweepExpiredRecords()
        session.selectedSpaceID = session.selectedSpaceID ?? session.spaces[0].id
        for i in session.downloads.indices where [.running, .choosing].contains(session.downloads[i].status) {
            session.downloads[i].status = session.downloads[i].resumeData == nil ? .failed : .paused
            session.downloads[i].error = "The previous download was interrupted."
        }
        showsRecoveryNotice = saved.recovered
    }

    func startMaintenance() {
        guard maintenance == nil else { return }
        maintenance = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(2)) } catch { break }
                guard let self else { break }
                for page in Array(pages.values) where pageMaintenance[page.id] == nil {
                    let id = page.id
                    pageMaintenance[id] = Task { [weak self, weak page] in
                        guard let self else { return }
                        defer { pageMaintenance[id] = nil }
                        guard let page, pages[id] === page else { return }
                        await page.refreshPageState()
                        await page.captureDocumentState()
                        if !visiblePageIDs.contains(page.id), !page.isProtectedFromUnloading,
                            Date().timeIntervalSince(page.lastSelected) >= 300
                        {
                            _ = await unloadSafely(page.id, automatic: true)
                        }
                    }
                }
                sweepExpiredRecords()
                media?.refresh()
            }
        }
    }

    var visiblePageIDs: Set<UUID> {
        Set(contexts.values.filter { !$0.isClosed }.flatMap { $0.visiblePages.map(\.id) })
    }

    func makeStore(restoring state: BrowserWindowState? = nil, spaceID: UUID? = nil) -> BrowserStore {
        var state =
            state
            ?? BrowserWindowState(
                spaceID: spaceID ?? session.selectedSpaceID ?? session.spaces.first(where: { !$0.isPrivate })!.id)
        if !session.spaces.contains(where: { $0.id == state.spaceID }) { state.spaceID = session.spaces[0].id }
        if let index = session.windows.firstIndex(where: { $0.id == state.id }) {
            session.windows[index] = state
        } else {
            session.windows.append(state)
        }
        let context = BrowserStore(owner: self, id: state.id)
        contexts[state.id] = context
        activeWindowID = state.id
        return context
    }

    func tabIndex(_ id: UUID) -> (Int, Int)? {
        for s in session.spaces.indices {
            if let t = session.spaces[s].tabs.firstIndex(where: { $0.id == id }) { return (s, t) }
        }
        return nil
    }

    func pageChanged(_ page: BrowserPage) {
        guard let (s, t) = tabIndex(page.id) else { return }
        var tab = session.spaces[s].tabs[t]
        if let url = page.url { tab.url = url }
        if !page.title.isEmpty { tab.title = page.title }
        if let icon = page.favicon, icon.count <= 32_768 { tab.favicon = icon }
        guard tab != session.spaces[s].tabs[t] else { return }
        session.spaces[s].tabs[t] = tab
        changed()
    }

    func unload(_ id: UUID) {
        pages[id]?.checkpointNativeState()
        pages.removeValue(forKey: id)?.invalidate()
        media?.refresh()
        runtimeRevision &+= 1
    }

    func changed() {
        session.revision &+= 1
        scheduleSave()
    }

    private func scheduleSave() {
        guard savingRevision == nil else { return }
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(350)) } catch { return }
            self?.saveInBackground()
        }
    }

    private func saveInBackground() {
        saveTask = nil
        let revision = session.revision
        savingRevision = revision
        persistence.save(checkpoint()) { [weak self] result in
            Task { @MainActor in
                guard let self, self.savingRevision == revision else { return }
                self.savingRevision = nil
                self.recordSave(result)
                if self.session.revision != revision { self.scheduleSave() }
            }
        }
    }

    @discardableResult func flush() -> Bool {
        saveTask?.cancel()
        saveTask = nil
        savingRevision = nil
        let snapshot = checkpoint()
        return recordSave(Result { try persistence.save(snapshot) })
    }

    private func checkpoint() -> BrowserSession {
        for page in pages.values { page.checkpointNativeState() }
        return session
    }

    @discardableResult
    private func recordSave(_ result: Result<Void, Error>) -> Bool {
        switch result {
        case .success:
            storageError = nil
            return true
        case .failure(let error):
            storageError = error.localizedDescription
            return false
        }
    }

    func setWindowFrame(_ id: UUID, frame: NSRect) {
        guard let index = session.windows.firstIndex(where: { $0.id == id }) else { return }
        let frame = NSStringFromRect(frame)
        guard session.windows[index].frame != frame else { return }
        session.windows[index].frame = frame
        changed()
    }

    func canCloseAll() async -> Bool {
        let loaded = Set(pages.keys)
        let tabs = Set(session.spaces.flatMap { $0.tabs.map(\.id) })
        let check = BrowserPageCloseCheck(Array(loaded), owner: self)
        func isCurrent() -> Bool {
            Set(pages.keys) == loaded && Set(session.spaces.flatMap { $0.tabs.map(\.id) }) == tabs
                && check.isCurrent(in: self)
        }
        guard await check.prepare(in: self), isCurrent() else { return false }
        let requests = activeDownloadRequests()
        if !requests.isEmpty {
            let starting = !pendingDownloads.isEmpty
            let alert = NSAlert()
            alert.messageText = "Downloads are still running"
            alert.informativeText =
                starting
                ? "Pause active downloads and cancel starting requests before quitting? Starting requests will need to restart."
                : "Pause resumable downloads before quitting? Private downloads and downloads that cannot resume will need to restart."
            alert.addButton(withTitle: "Keep Browsing")
            alert.addButton(withTitle: starting ? "Stop Downloads and Quit" : "Pause Downloads and Quit")
            guard await BrowserDialogs.ask(alert) == .alertSecondButtonReturn, isCurrent(),
                downloadRequestsMatch(requests)
            else { return false }
            for id in requests.keys {
                guard isCurrent(), downloadRequestsMatch(requests) else { return false }
                if pendingDownloads[id] != nil { cancelPendingDownload(id) }
                guard let job = downloads.values.first(where: { $0.id == id && $0.isActive }) else { continue }
                if session.spaces.first(where: { $0.id == job.spaceID })?.isPrivate == true {
                    job.cancel()
                } else {
                    await job.pause()
                }
            }
        }
        guard isCurrent(), activeDownloadRequests().isEmpty else { return false }
        guard flush() else {
            let alert = NSAlert()
            alert.messageText = "The session could not be saved"
            alert.informativeText = storageError ?? "The previous saved session is intact."
            alert.addButton(withTitle: "Keep Browsing")
            alert.addButton(withTitle: "Quit Without Saving")
            return await BrowserDialogs.ask(alert) == .alertSecondButtonReturn && isCurrent()
                && activeDownloadRequests().isEmpty
        }
        return true
    }
}

@MainActor enum BrowserDialogs {
    static func ask(_ alert: NSAlert, in window: NSWindow? = NSApp.keyWindow) async -> NSApplication.ModalResponse {
        if let window, window.attachedSheet == nil {
            return await withCheckedContinuation { continuation in
                alert.beginSheetModal(for: window) { continuation.resume(returning: $0) }
            }
        }
        return alert.runModal()
    }
}
