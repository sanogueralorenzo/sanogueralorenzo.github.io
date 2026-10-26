import AppKit
import Observation
import SwiftUI

/// Native presentation state only. Installation, permissions, pinning, workers,
/// and package storage remain owned by Chromium's independent Space profiles.
@Observable @MainActor
final class ChromiumExtensionStore {
    struct Installed: Identifiable {
        let id: String
        let name: String
        let version: String
        let detail: String
        let icon: NSImage?
        let enabled: Bool
        let permissions: [String]
        let webStore: Bool
        let options: String
        init(_ item: InstalledExtension) {
            id = item.id
            name = item.name.isEmpty ? item.id : item.name
            version = item.version
            detail = item.description
            icon = item.icon.flatMap(NSImage.init(extensionIcon:))
            enabled = item.enabled
            permissions = item.permissions
            webStore = item.fromWebStore
            options = item.optionsURL ?? ""
        }
    }
    var revision = 0
    private(set) var installed: [UUID: [Installed]] = [:]
    private(set) var installation: ChromiumExtensionInstallation?
    /// The extensions an import brought that still await their install review.
    @ObservationIgnored private var pendingImports: [ImportExtensionInstall] = []
    @ObservationIgnored private var importsTask: Task<Void, Never>?
    @ObservationIgnored private var popover: NSPopover?
    @ObservationIgnored private var windowClosed: NSObjectProtocol?
    /// The one-point view the install review is anchored to. It belongs to the
    /// window's own hosting view and is removed with the review.
    @ObservationIgnored private var anchorSpot: NSView?
    /// Runs when the presented install operation ends, however it ended. The
    /// Chrome Web Store listing that started it uses this to restate its own
    /// button instead of leaving it in the progress label.
    @ObservationIgnored private var installCompletion: (@MainActor () -> Void)?

    var spaces: [BrowserSpaceIdentity] { ChromiumComposition.extensionSpaces }
    /// Whether this Space's engine profile may be read and prepared here.
    ///
    /// Ownership is decided by `(spaceID, profileID)` against the store family
    /// that owns the window asking, not by identity against one global list: a
    /// window's own store publishes its Spaces before the application-wide list
    /// a start-up read would see. A Space from an unrelated family — another
    /// family's window, a borrowed settings workspace, a private window, which
    /// has no persistent engine profile of its own — and a locked Space are all
    /// refused. Callers with no window fall back to the application list.
    func authorized(_ space: BrowserSpaceIdentity, in browser: BrowserStore? = nil) -> Bool {
        guard !ChromiumComposition.isSpaceLocked(space) else { return false }
        guard let browser else {
            return spaces.contains { $0.id == space.id && $0.profileID == space.profileID }
        }
        guard ChromiumComposition.ownsExtensionProfiles(browser) else { return false }
        return browser.spaceModel(matching: space.assignment) != nil
    }
    func refresh() {
        revision &+= 1
        guard ChromiumComposition.chromiumEngine != nil else { return }
        let profiles = Set(spaces.map { $0.profileID })
        installed = installed.filter { profiles.contains($0.key) }
        for space in spaces where installed[space.profileID] != nil {
            installed[space.profileID] = Self.installed(in: space)
        }
    }

    /// What the engine has installed in the Space's profile.
    private static func installed(in space: BrowserSpaceIdentity) -> [Installed] {
        guard ChromiumComposition.engineHost != nil, let pages = ChromiumComposition.chromiumEngine?.pages else {
            return []
        }
        return pages.request(InstalledExtensions(profileID: space.profileID)).extensions.map(Installed.init)
    }
    func load(_ space: BrowserSpaceIdentity, in browser: BrowserStore? = nil) async {
        guard authorized(space, in: browser), let engine = ChromiumComposition.chromiumEngine else { return }
        let ready = await engine.prepareProfile(space.profileID)
        guard ready, authorized(space, in: browser) else { return }
        installed[space.profileID] = Self.installed(in: space)
        revision &+= 1
    }
    func actions(for page: ChromiumNativePage) -> [BrowserExtensionActionPresentation] {
        _ = revision
        return page.extensions
    }
    /// The pinned actions of a Space's own toolbar row.
    ///
    /// The row belongs to the Space, so the pinned list comes from the Space's
    /// profile and is present whether or not a page is open. Where a page is
    /// open its per-tab state — badge, dynamic icon, whether a page action has
    /// anything to act on — is overlaid on top of it.
    func pinnedActions(
        for space: BrowserSpaceIdentity, page: ChromiumNativePage?
    ) -> [BrowserExtensionActionPresentation] {
        _ = revision
        guard ChromiumComposition.engineHost != nil, let pages = ChromiumComposition.chromiumEngine?.pages else {
            return []
        }
        let live = Dictionary(
            page?.extensions.map { ($0.id, $0) } ?? [],
            uniquingKeysWith: { first, _ in first })
        return pages.request(PinnedExtensions(profileID: space.profileID)).actions
            .map { action -> BrowserExtensionActionPresentation in
                if let tab = live[action.id] {
                    return BrowserExtensionActionPresentation(
                        id: tab.id, displayName: tab.displayName,
                        badgeText: tab.badgeText, icon: tab.icon, isPinned: true)
                }
                return BrowserExtensionActionPresentation(action)
            }
            .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
    }
    /// Runs a pinned action from a Space with no page open. Only an action with
    /// its own popup can run without one, so anything else states itself as
    /// unavailable rather than doing nothing.
    func runPinned(
        _ action: BrowserExtensionActionPresentation, space: BrowserSpaceIdentity,
        anchor: BrowserExtensionPopupAnchor?
    ) {
        let fallback = ChromiumComposition.activeNativeWindow
        let anchor =
            anchor
            ?? BrowserExtensionPopupAnchor(
                screenPoint: NSEvent.mouseLocation,
                sourceWindow: fallback)
        guard let host = ChromiumComposition.engineHost,
            let source = anchor.presentationSource(fallbackWindow: fallback),
            let windowID = source.view.window?.identifier.flatMap({ UUID(uuidString: $0.rawValue) }),
            host.runExtension(
                action.id, profile: space.profileID, window: windowID,
                anchorView: source.view, anchorRect: source.rect)
        else {
            ChromiumComposition.showNativeNotice(
                String(localized: "This extension action needs an open page."),
                icon: "puzzlepiece.extension")
            return
        }
    }
    /// Makes sure the Space's engine profile is loaded so its pinned list can be
    /// read before anything has been opened in it.
    ///
    /// Idempotent: the Space keeps whatever the engine reported, so the row can
    /// ask on every appearance and every Space change. A Space the window's own
    /// store does not own — a private window's, a borrowed workspace's — is left
    /// alone; its profile exists only while a page of its own does.
    func prepare(_ space: BrowserSpaceIdentity, in browser: BrowserStore? = nil) async {
        guard installed[space.profileID] == nil, authorized(space, in: browser) else { return }
        await load(space, in: browser)
    }
    /// Runs `command` for the extension `extensionID` names in `space`: opens
    /// the page it names in `window`, or makes its change and restates what
    /// the store lists. False when the Space is not one this window may
    /// change, or when the command has nothing to open and no change to make.
    @discardableResult
    func command(
        _ command: ExtensionCommand, extensionID: String = "", space: BrowserSpaceIdentity, window: NSWindow? = nil
    ) -> Bool {
        guard authorized(space), let pages = ChromiumComposition.chromiumEngine?.pages,
            let window = window ?? ChromiumComposition.activeNativeWindow
        else { return false }
        let options = installed[space.profileID]?.first { $0.id == extensionID }?.options
        if let destination = command.destination(extensionID, options), let url = URL(string: destination) {
            return ChromiumComposition.openExtensionURL(url, in: space, window: window)
        }
        guard let change = command.change else { return false }
        let accepted = pages.request(
            ChangeExtension(profileID: space.profileID, extensionID: extensionID, change: change))
        refresh()
        return accepted
    }
    func togglePin(_ action: BrowserExtensionActionPresentation, space: BrowserSpaceIdentity) {
        _ = command(action.isPinned ? .unpin : .pin, extensionID: action.id, space: space)
    }
    /// Reports the installed record backing an action so the menu can offer only
    /// the verbs the extension actually supports. The profile is already prepared
    /// whenever an action is presented, so the host answers synchronously.
    private func installedRecord(_ extensionID: String, in space: BrowserSpaceIdentity) -> Installed? {
        if let cached = installed[space.profileID] { return cached.first { $0.id == extensionID } }
        guard authorized(space) else { return nil }
        let items = Self.installed(in: space)
        guard !items.isEmpty else { return nil }
        installed[space.profileID] = items
        revision &+= 1
        return items.first { $0.id == extensionID }
    }
    /// - Parameter openSidePanel: Supplied only when the extension has a side
    ///   panel entry for the page the action was presented on. The caller owns
    ///   the window the panel would mount into, so it also owns the check.
    /// - Parameter closeSource: Closes the surface the menu opened over, such
    ///   as Site Controls, before an item that leads somewhere else runs. The
    ///   surface stays open while the menu shows and when it is dismissed.
    func presentMenu(
        _ action: BrowserExtensionActionPresentation, space: BrowserSpaceIdentity,
        anchor: BrowserExtensionPopupAnchor?, isPrivate: Bool = false,
        openSidePanel: (@MainActor () -> Void)? = nil,
        closeSource: (() -> Void)? = nil
    ) {
        let menu = NSMenu(title: action.displayName)
        menu.autoenablesItems = false
        let handler = ExtensionMenuHandler(closeSource: closeSource)
        let record = installedRecord(action.id, in: space)
        if let openSidePanel {
            menu.addItem(handler.item(String(localized: "Open Side Panel")) { openSidePanel() })
            menu.addItem(.separator())
        }
        // A private window must never change the Space's persistent extension
        // state, so only the navigation verbs are offered from one.
        if !isPrivate {
            if record.map({ !$0.options.isEmpty && $0.enabled }) ?? true {
                menu.addItem(
                    handler.item(String(localized: "Extension Settings…")) { [weak self] in
                        self?.command(.options, extensionID: action.id, space: space)
                    })
            }
            menu.addItem(
                handler.item(
                    action.isPinned
                        ? String(localized: "Unpin from Toolbar") : String(localized: "Pin to Toolbar"),
                    keepsSource: true
                ) { [weak self] in
                    self?.togglePin(action, space: space)
                })
            if let record {
                menu.addItem(
                    handler.item(
                        record.enabled
                            ? String(localized: "Disable Extension") : String(localized: "Enable Extension")
                    ) { [weak self] in
                        self?.command(record.enabled ? .disable : .enable, extensionID: action.id, space: space)
                    })
            }
            menu.addItem(.separator())
        }
        menu.addItem(
            handler.item(String(localized: "Manage Extension…")) { [weak self] in
                self?.command(.details, extensionID: action.id, space: space)
            })
        menu.addItem(
            handler.item(String(localized: "Manage Extensions…")) { [weak self] in
                self?.command(.manage, space: space)
            })
        if record?.webStore ?? false {
            menu.addItem(
                handler.item(String(localized: "View on Chrome Web Store")) { [weak self] in
                    self?.command(.store, extensionID: action.id, space: space)
                })
        }
        if !isPrivate, let record {
            menu.addItem(.separator())
            menu.addItem(
                handler.item(String(localized: "Remove Extension…")) { [weak self] in
                    self?.confirmRemoval(record, space: space)
                })
        }
        if let source = anchor?.presentationSource(fallbackWindow: ChromiumComposition.activeNativeWindow) {
            menu.popUp(positioning: nil, at: NSPoint(x: source.rect.minX, y: source.rect.minY), in: source.view)
        } else {
            menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
        }
        withExtendedLifetime(handler) {}
    }
    /// Removal asked for by identifier — the Chrome Web Store listing for an
    /// extension already installed in this Space. The confirmation, the Space's
    /// ownership check and the engine command are the menu's own.
    func confirmRemoval(
        _ extensionID: String, in space: BrowserSpaceIdentity,
        completion: (@MainActor () -> Void)? = nil
    ) {
        guard let record = installedRecord(extensionID, in: space) else {
            completion?()
            return
        }
        confirmRemoval(record, space: space, completion: completion)
    }
    /// Mirrors the confirmation the extension settings pane requires before an
    /// uninstall. The menu's tracking loop owns the event while an item runs, so
    /// the alert is presented once the menu has dismissed.
    private func confirmRemoval(
        _ record: Installed, space: BrowserSpaceIdentity,
        completion: (@MainActor () -> Void)? = nil
    ) {
        Task { @MainActor [weak self] in
            await Task.yield()
            guard let self, self.authorized(space) else {
                completion?()
                return
            }
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = String(localized: "Remove \(record.name)?")
            alert.informativeText = String(
                localized:
                    "\(record.name) and its Space-local data will be removed. Other Spaces are unchanged.")
            alert.addButton(withTitle: String(localized: "Remove from \(space.name)"))
            alert.addButton(withTitle: String(localized: "Cancel"))
            alert.buttons.first?.hasDestructiveAction = true
            let complete: (NSApplication.ModalResponse) -> Void = { response in
                MainActor.assumeIsolated {
                    defer { completion?() }
                    guard response == .alertFirstButtonReturn else { return }
                    guard self.command(.remove, extensionID: record.id, space: space) else {
                        self.reportFailure()
                        return
                    }
                }
            }
            if let window = ChromiumComposition.activeNativeWindow {
                alert.beginSheetModal(for: window, completionHandler: complete)
            } else {
                complete(alert.runModal())
            }
        }
    }
    /// Says what an import's extensions came to: those installed, and those
    /// that could not be.
    private func reportImportedInstalls(added: [String], failed: [String]) {
        if !added.isEmpty {
            BrowserNoticeCenter.shared.post(
                BrowserNotice(
                    message: added.count == 1
                        ? String(localized: "Installed \(added[0])")
                        : String(localized: "Installed \(added.count) extensions"),
                    systemImage: "puzzlepiece.extension.fill"))
        }
        if !failed.isEmpty {
            BrowserNoticeCenter.shared.post(
                BrowserNotice(
                    message: String(localized: "Couldn’t install \(failed.formatted(.list(type: .and)))"),
                    systemImage: "exclamationmark.triangle"))
        }
    }
    private func reportFailure() {
        BrowserNoticeCenter.shared.post(
            BrowserNotice(
                message: String(
                    localized:
                        "Couldn’t complete that extension action. Check its details for policy or permission requirements."
                ),
                systemImage: "exclamationmark.triangle"))
    }
    /// Installs the extensions an import brought, one at a time and without
    /// asking again: the person chose each when they reviewed the import.
    /// Chromium still verifies every package for each Space it goes into. An
    /// extension that goes into several Spaces is downloaded once, then
    /// installed in each of them. It waits for the Spaces and a browser window
    /// to exist, leaves out a Space that already has the extension, and says
    /// once, when the queue empties, what it installed and what it could not.
    func installImported(_ installs: [ImportExtensionInstall]) {
        pendingImports += installs
        guard importsTask == nil else { return }
        importsTask = Task { [weak self] in
            await self?.runPendingImports()
            self?.importsTask = nil
        }
    }
    private func runPendingImports() async {
        var added: [String] = []
        var failed: [String] = []
        defer { reportImportedInstalls(added: added, failed: failed) }
        while !pendingImports.isEmpty, !Task.isCancelled {
            let next = pendingImports.removeFirst()
            var wanted: [BrowserSpaceIdentity] = []
            for id in next.spaceIDs {
                guard let space = await importedSpace(id) else { continue }
                await load(space)
                let alreadyHas = installed[space.profileID]?.contains { $0.id == next.extensionID } == true
                if !alreadyHas, !wanted.contains(where: { $0.id == space.id }) { wanted.append(space) }
            }
            // One install runs at a time and the engine routes its consent through a browser window. Either
            // can change while this waits, so the Spaces still within reach are chosen when the install
            // starts, with nothing awaited between that check and the call.
            while !Task.isCancelled {
                let reachable = wanted.filter { space in
                    authorized(space) && installed[space.profileID]?.contains { $0.id == next.extensionID } != true
                }
                guard let first = reachable.first else { break }
                if installation == nil, let window = ChromiumComposition.activeNativeWindow {
                    let job = ChromiumExtensionInstallation(
                        id: next.extensionID, space: first, window: window, store: self, approvesItself: true)
                    job.selectedSpaces = Set(reachable.dropFirst().map(\.id))
                    installation = job
                    await job.start()
                    if installation === job { installation = nil }
                    if job.completed { added.append(job.questionName ?? next.name) } else { failed.append(next.name) }
                    break
                }
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
    }
    /// The Space `id` once the engine may act in it and a browser window is
    /// open to present the review. It waits for the window however long that
    /// takes, since setup holds the browser's windows back until the person
    /// opens Crest, and gives up only on a Space that never appears or stays
    /// out of reach.
    private func importedSpace(_ id: UUID) async -> BrowserSpaceIdentity? {
        var missing = 0
        while !Task.isCancelled {
            if let space = spaces.first(where: { $0.id == id }), authorized(space) {
                if ChromiumComposition.activeNativeWindow != nil { return space }
                missing = 0
            } else {
                missing += 1
                if missing >= 60 { return nil }
            }
            try? await Task.sleep(for: .milliseconds(500))
        }
        return nil
    }
    func install(
        _ id: String, in space: BrowserSpaceIdentity, anchor: NSView?, copies: Set<UUID> = [],
        completion: (@MainActor () -> Void)? = nil
    ) {
        guard installation == nil, authorized(space),
            let window = anchor?.window ?? ChromiumComposition.activeNativeWindow
        else {
            completion?()
            return
        }
        installCompletion = completion
        let job = ChromiumExtensionInstallation(id: id, space: space, window: window, store: self)
        job.selectedSpaces = copies
        installation = job
        let popover = NSPopover()
        popover.behavior = .applicationDefined
        popover.contentViewController = NSHostingController(rootView: BrowserChromeWebStoreInstallView(model: job))
        self.popover = popover
        // Anchor native presentation in Crest's hosting view. Anchoring it in
        // Chromium's responder subtree lets web focus consume popover input.
        guard let source = window.contentView else {
            dismissInstallation()
            return
        }
        // AppKit reads a caller's positioning rectangle as if the view were not
        // flipped, and SwiftUI's hosting view is flipped: a rectangle measured
        // from its top edge presented the review past the window's lower edge
        // and off the screen. A one-point positioning view carries the anchor
        // instead, because a subview's own frame is resolved in its superview's
        // coordinate space whichever way that space runs.
        let spot = NSView(
            frame: NSRect(
                x: min(160, source.bounds.width / 2),
                y: source.isFlipped ? 44 : source.bounds.height - 44, width: 1, height: 1))
        source.addSubview(spot)
        anchorSpot = spot
        popover.show(relativeTo: .zero, of: spot, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        windowClosed = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: window, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.dismissInstallation() }
        }
        Task { await job.start() }
    }
    /// The engine asks whether to install the package the install operation of
    /// the window `asked` names verified.
    func review(_ asked: ExtensionInstallAsked, reply: @escaping (Bool, Bool) -> Void) {
        let review = asked.question
        guard let job = installation, job.window?.identifier?.rawValue == asked.windowID.uuidString,
            review.extensionID == job.id
        else {
            // No user-owned install operation may inherit an unrelated consent.
            reply(false, false)
            return
        }
        job.review(review, reply: reply)
    }
    func dismissInstallation() {
        installation?.cancel()
        installation = nil
        popover?.close()
        popover = nil
        if let windowClosed { NotificationCenter.default.removeObserver(windowClosed) }
        windowClosed = nil
        anchorSpot?.removeFromSuperview()
        anchorSpot = nil
        let completion = installCompletion
        installCompletion = nil
        completion?()
    }
}

extension ChromiumExtensionStore: BrowserImportedExtensionInstalling {}

/// Owns the menu item closures; `NSMenuItem.target` is weak, so this has to
/// outlive the menu's tracking loop.
@MainActor private final class ExtensionMenuHandler: NSObject {
    private let closeSource: (() -> Void)?
    private var handlers: [() -> Void] = []

    init(closeSource: (() -> Void)?) {
        self.closeSource = closeSource
    }

    /// - Parameter keepsSource: The item changes something the source surface
    ///   shows, so the surface stays open after it runs.
    func item(_ title: String, keepsSource: Bool = false, perform: @escaping () -> Void) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(invoke(_:)), keyEquivalent: "")
        item.target = self
        item.isEnabled = true
        item.tag = handlers.count
        if keepsSource || closeSource == nil {
            handlers.append(perform)
        } else {
            handlers.append { [closeSource] in
                closeSource?()
                Task { @MainActor in
                    await Task.yield()
                    perform()
                }
            }
        }
        return item
    }
    @objc private func invoke(_ sender: NSMenuItem) {
        guard handlers.indices.contains(sender.tag) else { return }
        handlers[sender.tag]()
    }
}

@Observable @MainActor
final class ChromiumExtensionInstallation {
    let id: String
    let space: BrowserSpaceIdentity
    weak var window: NSWindow?
    private let store: ChromiumExtensionStore
    /// The verified package the core asks the person about, as its question
    /// presents it.
    var question: ExtensionInstallQuestion?
    /// The name the review shows: the package's own, or its identifier when
    /// it names none.
    var questionName: String? { question.map { $0.name.isEmpty ? $0.extensionID : $0.name } }
    var questionIcon: NSImage? { question?.icon.flatMap(NSImage.init(data:)) }
    var selectedSpaces: Set<UUID> = []
    var withhold = false
    var canWithhold = false
    var preparing = true
    /// The fraction of the package received, once its download knows its size.
    var downloaded: Double?
    var installing = false
    var completed = false
    var installedCount = 0
    var failure: String?
    var canAccept = false
    @ObservationIgnored private var consent: ((Bool, Bool) -> Void)?
    @ObservationIgnored private var approvedIdentity: [String]?
    @ObservationIgnored private var approvedDestinations: [BrowserSpaceIdentity] = []
    @ObservationIgnored private var package: URL?
    /// The package download while it runs, so closing the review stops it.
    @ObservationIgnored private var transfer: (any CrestExtensionDownload)?
    @ObservationIgnored private var canceled = false
    @ObservationIgnored private var targetSpace: BrowserSpaceIdentity?

    /// Whether the install accepts the engine's question itself, as an
    /// import's does: the person chose the extension when they reviewed it.
    private let approvesItself: Bool

    init(
        id: String, space: BrowserSpaceIdentity, window: NSWindow, store: ChromiumExtensionStore,
        approvesItself: Bool = false
    ) {
        self.id = id
        self.space = space
        self.window = window
        self.store = store
        self.approvesItself = approvesItself
    }
    var isAuthorized: Bool { store.authorized(space) && (targetSpace.map { store.authorized($0) } ?? true) }
    var destinations: [BrowserSpaceIdentity] {
        store.spaces.filter { $0.id != space.id && !(store.installed[$0.profileID] ?? []).contains { $0.id == id } }
    }
    func start() async {
        for target in store.spaces { await store.load(target) }
        guard !canceled else { return }
        do {
            let retained = try await download()
            package = retained
            defer {
                try? FileManager.default.removeItem(at: retained)
                package = nil
            }
            guard !canceled else { return }
            try await installPackage(in: space)
            installedCount = 1
            // Freeze the explicitly reviewed targets and package; every copy is
            // independently verified by Chromium and keeps its own profile data,
            // so a Space that refuses its copy leaves the others to install.
            for target in approvedDestinations {
                guard !canceled else { return }
                guard (try? await installPackage(in: target)) != nil else { continue }
                installedCount += 1
            }
            completed = true
            store.refresh()
        } catch {
            if !canceled { failure = error.localizedDescription }
        }
        preparing = false
        installing = false
    }
    /// The package as the Space's own engine profile downloads it; Chromium's
    /// installer then judges it for every Space it is installed in.
    private func download() async throws -> URL {
        guard let host = ChromiumComposition.engineHost else { throw URLError(.cancelled) }
        let result: (String?, String) = await withCheckedContinuation { continuation in
            transfer = host.downloadExtension(
                id, profile: space.profileID,
                progress: { [weak self] fraction in self?.downloaded = fraction },
                completion: { package, message in
                    continuation.resume(returning: (package, message))
                })
            if transfer == nil { continuation.resume(returning: (nil, "")) }
        }
        transfer = nil
        guard let package = result.0 else {
            throw NSError(
                domain: "CrestExtension", code: 2,
                userInfo: [
                    NSLocalizedDescriptionKey: result.1.isEmpty
                        ? String(localized: "The Space is no longer available.")
                        : String(localized: "Couldn’t download this extension from the Chrome Web Store (\(result.1)).")
                ])
        }
        return URL(fileURLWithPath: package)
    }
    private func installPackage(in target: BrowserSpaceIdentity) async throws {
        guard !canceled, store.authorized(target), let package, let host = ChromiumComposition.engineHost,
            let windowID = window?.identifier.flatMap({ UUID(uuidString: $0.rawValue) })
        else { throw URLError(.cancelled) }
        targetSpace = target
        let staged = FileManager.default.temporaryDirectory.appendingPathComponent("crest-extension-\(UUID()).crx")
        try FileManager.default.copyItem(at: package, to: staged)
        defer { try? FileManager.default.removeItem(at: staged) }
        let result: (Bool, String) = await withCheckedContinuation { continuation in
            if !host.installExtension(
                id, package: staged.path, profile: target.profileID, window: windowID,
                completion: { success, message in
                    continuation.resume(returning: (success, message))
                })
            {
                continuation.resume(returning: (false, "The Space is no longer available."))
            }
        }
        guard result.0 else {
            throw NSError(
                domain: "CrestExtension", code: 1,
                userInfo: [NSLocalizedDescriptionKey: result.1.isEmpty ? "Installation canceled." : result.1])
        }
    }
    func review(_ review: ExtensionInstallQuestion, reply: @escaping (Bool, Bool) -> Void) {
        guard !canceled, store.authorized(space), let targetSpace, store.authorized(targetSpace) else {
            reply(false, false)
            return
        }
        if let approvedIdentity {
            // Consent applies only to the same verified package and warnings.
            reply(Self.consentIdentity(of: review) == approvedIdentity, withhold)
            return
        }
        question = review
        canWithhold = review.canWithholdSiteAccess
        withhold = review.withholdsSiteAccess
        if approvesItself {
            approvedIdentity = Self.consentIdentity(of: review)
            approvedDestinations = destinations.filter { selectedSpaces.contains($0.id) }
            installing = true
            reply(true, withhold)
            return
        }
        consent = reply
        preparing = false
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            self?.canAccept = true
        }
    }
    func accept() {
        guard canAccept, let question, store.authorized(space), let consent else { return }
        approvedIdentity = Self.consentIdentity(of: question)
        approvedDestinations = destinations.filter { selectedSpaces.contains($0.id) }
        self.consent = nil
        installing = true
        consent(true, withhold)
    }
    func cancel() {
        canceled = true
        // The download then reports failure, which a canceled review ignores.
        transfer?.cancel()
        transfer = nil
        let callback = consent
        consent = nil
        callback?(false, false)
    }
    func dismiss() { store.dismissInstallation() }

    /// What a consent covers: the same verified package, at the same version,
    /// asking for the same access.
    private static func consentIdentity(of question: ExtensionInstallQuestion) -> [String] {
        [question.extensionID, question.version] + question.permissions.sorted()
    }
}
