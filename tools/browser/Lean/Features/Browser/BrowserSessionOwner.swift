import AppKit
import Foundation
import Observation
import WebKit

/// The only authoritative browser state, shared by every ordinary window.
@MainActor @Observable
final class BrowserSessionOwner {
    var session: BrowserSession
    let persistence: BrowserPersistence
    var pages: [UUID: BrowserPage] = [:]
    var profiles: [UUID: WKWebsiteDataStore] = [:]
    var contentBlockers: [UUID: BrowserContentBlocking] = [:]
    var integrations: [UUID: GitHubFolder] = [:]
    var downloads: [ObjectIdentifier: BrowserDownload] = [:]
    var contexts: [UUID: BrowserStore] = [:]
    var runtimeRevision = 0
    var lastRetentionSweep = Date.distantPast
    var storageError: String?
    var activeWindowID: UUID?
    var sidebarDrag: BrowserDragPayload?
    @ObservationIgnored var sidebarDragSource: BrowserSidebarDragSourceView?
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var maintenance: Task<Void, Never>?
    @ObservationIgnored private var pageMaintenance: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored var openWindow: ((BrowserWindowState?) -> Void)?
    @ObservationIgnored var media: BrowserSystemMedia?

    init() throws {
        persistence = try BrowserPersistence()
        session = try persistence.load()
        sweepExpiredRecords()
        session.selectedSpaceID = session.selectedSpaceID ?? session.spaces[0].id
        for i in session.downloads.indices where session.downloads[i].status == .running {
            session.downloads[i].status = session.downloads[i].resumeData == nil ? .failed : .paused
            session.downloads[i].error = "The previous download was interrupted."
        }
        if persistence.recovered {
            storageError = "Recovered the previous saved session. The damaged file has been preserved."
        }
    }

    func startMaintenance() {
        guard maintenance == nil else { return }
        maintenance = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(2)) } catch { break }
                guard let self else { break }
                for page in Array(pages.values) where pageMaintenance[page.id] == nil {
                    pageMaintenance[page.id] = Task { [weak self, weak page] in
                        guard let self, let page else { return }
                        defer { pageMaintenance[page.id] = nil }
                        await page.readMediaState()
                        await page.captureDocumentState()
                        if !visiblePageIDs.contains(page.id), !page.isProtectedFromUnloading,
                            Date().timeIntervalSince(page.lastSelected) >= 300,
                            let store = page.owner
                        {
                            _ = await store.unloadSafely(page.id, automatic: true)
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
        state.isOpen = true
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

    func changed() {
        session.revision &+= 1
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(350)) } catch { return }
            self?.flush()
        }
    }

    @discardableResult func flush() -> Bool {
        saveTask?.cancel()
        for page in pages.values { page.checkpointNativeState() }
        do {
            try persistence.save(session)
            storageError = nil
            return true
        } catch {
            storageError = error.localizedDescription
            return false
        }
    }

    func setWindowFrame(_ id: UUID, frame: NSRect) {
        guard let index = session.windows.firstIndex(where: { $0.id == id }) else { return }
        session.windows[index].frame = NSStringFromRect(frame)
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
        let jobs = Array(downloads.values).filter { $0.isActive }
        if !jobs.isEmpty {
            let alert = NSAlert()
            alert.messageText = "Downloads are still running"
            alert.informativeText =
                "Pause resumable downloads before quitting? Private downloads and downloads that cannot resume will need to restart."
            alert.addButton(withTitle: "Keep Browsing")
            alert.addButton(withTitle: "Pause Downloads and Quit")
            guard await BrowserDialogs.ask(alert) == .alertSecondButtonReturn, isCurrent(),
                Set(downloads.values.filter(\.isActive).map(\.id)).isSubset(of: Set(jobs.map(\.id)))
            else { return false }
            for job in jobs {
                if session.spaces.first(where: { $0.id == job.spaceID })?.isPrivate == true {
                    job.cancel()
                } else {
                    await job.pause()
                }
            }
        }
        guard isCurrent(), !downloads.values.contains(where: \.isActive) else { return false }
        guard flush() else {
            let alert = NSAlert()
            alert.messageText = "The session could not be saved"
            alert.informativeText = storageError ?? "The previous saved session is intact."
            alert.addButton(withTitle: "Keep Browsing")
            alert.addButton(withTitle: "Quit Without Saving")
            return await BrowserDialogs.ask(alert) == .alertSecondButtonReturn && isCurrent()
                && !downloads.values.contains(where: \.isActive)
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
