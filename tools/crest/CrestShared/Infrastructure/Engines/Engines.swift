import Foundation
import OSLog
import Observation

// MARK: - Types

/// What an engine's binding built for the platform to host for one page the
/// core opened: WebKit's page, or the platform's host of a page an engine the
/// core runs directly created. Each platform hosts it its own way.
@MainActor
protocol EngineHostedPage: AnyObject {}

/// The engine bindings the core hosts pages on, by kind. A composition
/// registers the engines it carries, one of them as the default, and new pages
/// open on the default. The core decides whether a page opens and on which
/// engine; the binding builds what the platform hosts.
@MainActor
@Observable
final class Engines {
    // MARK: - Static Variables

    private static let logger = Logger(subsystem: "com.pauldavis.crest", category: "Pages")

    // MARK: - Types

    /// A page the platform asked the core to open, while the core asks its
    /// engine to create it.
    final class PageRequest {
        let page: CorePage
        /// What the platform asked for: the page's workspace, Space, tab and
        /// window.
        let intent: OpenPage
        /// What the engine's binding built for the platform to host.
        var built: (any EngineHostedPage)?

        init(page: CorePage, intent: OpenPage) {
            self.page = page
            self.intent = intent
        }
    }

    /// What the core recorded from pages' reports in one batch of changes:
    /// the navigations it recorded and the tabs that took their page's icon.
    struct PageRecords {
        var navigations: [NavigationRecorded] = []
        var icons: [TabFaviconAssigned] = []

        var isEmpty: Bool { navigations.isEmpty && icons.isEmpty }

        /// Whether the core recorded a navigation of `pageID`.
        func recordedNavigation(of pageID: UUID) -> Bool {
            navigations.contains { $0.pageID == pageID }
        }
    }

    /// One registration to hear page records, which lasts as long as its owner.
    private typealias RecordObserver = (owner: WeakOwner, handler: @MainActor (PageRecords) -> Void)

    /// A page the core opened, with what its engine's binding built for the
    /// platform to host: WebKit's page, or the platform's host of a page an
    /// engine the core runs directly created.
    struct OpenedPage {
        let page: CorePage
        let built: any EngineHostedPage
    }

    /// Carries the core's commands for one engine to its binding.
    final class Relay: @unchecked Sendable {
        let kind: EngineKind
        @MainActor weak var engines: Engines?

        @MainActor
        init(kind: EngineKind, engines: Engines) {
            self.kind = kind
            self.engines = engines
        }
    }

    // MARK: - Variables

    /// The registered bindings, by kind.
    private(set) var bindings: [EngineKind: any EngineBinding] = [:]
    /// The registered bindings the core runs directly, by kind. Their commands
    /// and reports never pass through here.
    @ObservationIgnored private var natives: [EngineKind: any NativeEngineBinding] = [:]
    /// The core's handle for each registered engine, and its relay, which the
    /// core addresses while the engine stays registered.
    @ObservationIgnored private var registered: [EngineKind: (engine: UInt64, relay: Relay)] = [:]
    @ObservationIgnored private var requests: [UUID: PageRequest] = [:]
    /// The engine that hosts each page the core asked one to create.
    @ObservationIgnored private var hosts: [UUID: EngineKind] = [:]
    /// The pages the core opened, while their owners keep them.
    @ObservationIgnored private var opened: [UUID: WeakPage] = [:]
    /// What an engine the core moved a page to built for it, until the page's
    /// owner takes it.
    @ObservationIgnored private var moved: [UUID: any EngineHostedPage] = [:]
    /// What a binding built for a page the core adopted from its engine's
    /// offer, such as a popup WebKit made, until the page's owner hosts it.
    @ObservationIgnored private var offered: [UUID: any EngineHostedPage] = [:]
    /// The icon each page last reported, until a tab adopts it and the bytes
    /// move to `FaviconAssets` under that tab.
    @ObservationIgnored private var pageIcons: [UUID: Data] = [:]
    /// Those who hear what the core recorded from pages' reports.
    @ObservationIgnored private var recordObservers: [RecordObserver] = []
    /// The core the bindings register with, which a binding follows for what
    /// it asks the person about its pages.
    @ObservationIgnored unowned let core: CrestCore

    // MARK: - Initializers

    init(core: CrestCore) {
        self.core = core
    }

    // MARK: - Actions - Registration

    /// Registers a binding with the core, as the engine new pages open on when
    /// `isDefault`. A refusal is a composition bug.
    func register(_ binding: any EngineBinding, isDefault: Bool) {
        let kind = binding.integration.kind
        let relay = Relay(kind: kind, engines: self)
        binding.attach(to: self)
        do {
            let engine = try core.registerEngine(binding.integration.registration(isDefault: isDefault), relay: relay)
            registered[kind] = (engine, relay)
            bindings[kind] = binding
        } catch {
            preconditionFailure("The core refused the \(kind.name) engine: \(error)")
        }
    }

    /// Registers a binding the core runs directly, as the engine new pages
    /// open on when `isDefault`. A refusal is a composition bug, or an engine
    /// built against another engine contract.
    func register(_ binding: any NativeEngineBinding, isDefault: Bool) {
        let kind = binding.integration.kind
        do {
            _ = try core.registerEngine(
                binding.integration.registration(isDefault: isDefault), table: binding.table,
                fingerprint: binding.fingerprint)
            natives[kind] = binding
        } catch {
            preconditionFailure("The core refused the \(kind.name) engine: \(error)")
        }
    }

    // MARK: - Actions - Pages

    /// Opens a page through the core and answers it with what its engine built,
    /// or nil when a rule refused it or the engine built nothing.
    func open(_ intent: OpenPage) -> OpenedPage? {
        let request = PageRequest(page: CorePage(id: intent.pageID, core: core), intent: intent)
        requests[intent.pageID] = request
        defer { requests[intent.pageID] = nil }
        do {
            try core.send(intent)
        } catch {
            Self.logger.debug("The core opened no page: \(String(describing: error))")
            return nil
        }
        guard let built = request.built ?? nativeHost(for: request.page) else {
            request.page.release(keepingState: false)
            return nil
        }
        opened[intent.pageID] = WeakPage(value: request.page)
        return OpenedPage(page: request.page, built: built)
    }

    /// What the shared page host hosts for a page the core opened itself,
    /// such as one an engine opened by itself that the core adopted: the page
    /// its engine's binding built for it, which WebKit's binding handed over,
    /// or the host of an engine the core runs directly. Nil when the core
    /// holds no such page or the platform already hosts it.
    func host(_ pageID: UUID) -> OpenedPage? {
        guard opened[pageID]?.value == nil else { return nil }
        let page = CorePage(id: pageID, core: core)
        guard let built = offered.removeValue(forKey: pageID) ?? nativeHost(for: page) else { return nil }
        opened[pageID] = WeakPage(value: page)
        return OpenedPage(page: page, built: built)
    }

    /// What the platform hosts for a page the core opened on an engine it runs
    /// directly, which creates the page on its own.
    private func nativeHost(for page: CorePage) -> (any EngineHostedPage)? {
        guard let kind = page.state?.engine, let binding = natives[kind] else { return nil }
        return binding.host(page)
    }

    /// The page the core opened as `pageID`, while its owner keeps it.
    func page(_ pageID: UUID) -> CorePage? {
        opened[pageID]?.value
    }

    /// The page the core is asking a binding to create, while its owner waits.
    func request(_ pageID: UUID) -> PageRequest? {
        requests[pageID]
    }

    // MARK: - Actions - Moving pages

    /// Hands the page's owner what `built` is: the page an engine built for a
    /// page the core moved to it. The owner takes it before the engine reports
    /// the page created, so the core's first load reaches the new page.
    func handOver(_ built: any EngineHostedPage, movedPage page: CorePage) {
        moved[page.id] = built
        page.engineMoved?()
    }

    /// Keeps `built`, the page a binding built for page `pageID`, which the
    /// core adopted from the binding's offer, until the page's owner hosts it.
    func handOver(_ built: any EngineHostedPage, adoptedPage pageID: UUID) {
        offered[pageID] = built
    }

    /// What the platform hosts for `page` now that the core moved it off
    /// engine `current`: the page its new engine's binding built, or the host
    /// of an engine the core runs directly. Nil when it did not move.
    func movedHost(for page: CorePage, from current: EngineKind) -> (any EngineHostedPage)? {
        if let built = moved.removeValue(forKey: page.id) { return built }
        guard let kind = page.state?.engine, kind != current, let binding = natives[kind] else { return nil }
        return binding.host(page)
    }

    /// Tells the owners of `pageIDs` the core moved their pages to another
    /// engine.
    func pagesMoved(_ pageIDs: [UUID]) {
        for pageID in pageIDs {
            opened[pageID]?.value?.engineMoved?()
        }
    }

    /// Reports what happened to one of `binding`'s pages. `icon` is the image
    /// a `PageIconChanged` names, which waits here for the tab that adopts it.
    func report(_ event: some EngineEvent, from binding: any EngineBinding, icon: (page: UUID, data: Data)? = nil) {
        report(event, on: binding.integration.kind, icon: icon)
    }

    /// Reports what happened to `pageID` through the engine that hosts it; a
    /// page no engine was asked to create reports nothing.
    func report(_ event: some EngineEvent, for pageID: UUID, icon: Data? = nil) {
        guard let kind = hosts[pageID] else { return }
        report(event, on: kind, icon: icon.map { (pageID, $0) })
    }

    /// What the core answers `binding` about one of its pages while its
    /// engine waits; nil for a binding that is not registered.
    func ask<Question: EngineQuestion>(_ question: Question, from binding: any EngineBinding) -> Question.Answer? {
        guard let engine = registered[binding.integration.kind]?.engine else { return nil }
        return core.ask(question, engine: engine)
    }

    /// The icon `pageID` reported, which leaves this store for the tab that
    /// adopts it.
    func takeIcon(of pageID: UUID) -> Data? {
        if let icon = pageIcons.removeValue(forKey: pageID) { return icon }
        // An engine the core runs directly keeps its pages' icons itself.
        return natives.values.lazy.compactMap { $0.icon(of: pageID) }.first
    }

    /// The page is gone, and nothing it reported waits here any longer.
    func forget(_ pageID: UUID) {
        hosts[pageID] = nil
        pageIcons[pageID] = nil
        opened[pageID] = nil
        moved[pageID] = nil
        offered[pageID] = nil
    }

    private func report(_ event: some EngineEvent, on kind: EngineKind, icon: (page: UUID, data: Data)?) {
        guard let engine = registered[kind]?.engine else { return }
        if let icon { pageIcons[icon.page] = icon.data }
        core.report(event, engine: engine)
    }

    // MARK: - Actions - Records

    /// Calls `handler` with what the core recorded from pages' reports in
    /// each batch it applies, once the whole batch is applied. The
    /// registration lasts as long as `owner`.
    func observeRecords(_ owner: AnyObject, _ handler: @escaping @MainActor (PageRecords) -> Void) {
        recordObservers.removeAll { $0.owner.value == nil }
        recordObservers.append((WeakOwner(value: owner), handler))
    }

    /// Tells the observers what a batch recorded from pages' reports.
    func recordsApplied(_ records: PageRecords) {
        recordObservers.removeAll { $0.owner.value == nil }
        for observer in recordObservers { observer.handler(records) }
    }

    // MARK: - Actions - Commands

    /// Hands a command the core issued to the binding it names. A page the
    /// core asks an engine to create is that engine's until it closes. The
    /// page itself stays the core's: one the core moves to another engine
    /// closes on this one and lives on, and its owner forgets it only when it
    /// lets it go.
    func run(_ command: EngineCommand, on kind: EngineKind) {
        command.note(runningOn: kind, in: &hosts)
        bindings[kind]?.run(command)
    }
}

/// A registration's owner, held weakly so the registration goes with it.
private struct WeakOwner {
    weak var value: AnyObject?
}

/// A page the core opened, held weakly so it goes with its owner.
private struct WeakPage {
    weak var value: CorePage?
}
