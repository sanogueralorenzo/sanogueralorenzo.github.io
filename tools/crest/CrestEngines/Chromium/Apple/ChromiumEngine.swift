#if CREST_CHROMIUM_HOST
    import CrestCoreABI
    import Foundation

    /// Chromium, the default engine. Its binding is the engine's own C++: the
    /// core hands it commands through the binding's function table, and the
    /// binding creates, loads and closes each page and reports what it does
    /// straight to the core. This hosts the pages' views, and its pages ask
    /// the binding for their view work directly.
    @MainActor
    final class ChromiumEngine: NativeEngineBinding {
        // MARK: - Static Variables

        /// The version the app's Chromium framework names, read without
        /// loading it.
        private static let bundledVersion: String? = {
            guard let frameworks = Bundle.main.privateFrameworksURL,
                let framework = Bundle(url: frameworks.appendingPathComponent("Chromium Framework.framework"))
            else { return nil }
            return framework.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        }()

        // MARK: - Variables

        let integration = BrowserEngineRegistration.chromium
        let table: crest_engine_binding_t
        let fingerprint: [UInt8]
        /// The Mac shell, for what only AppKit does.
        private(set) var host: (any CrestMacShell)?
        /// The pages' direct path to the binding, which hears the binding's
        /// presentations from the engine's start on.
        private(set) var pages: NativeEnginePages!
        /// The core that asks this engine's questions of the person and hears
        /// the answers. Weak: the composition owns it.
        private weak var core: CrestCore?
        /// What closes each question a page shows, until the core settles it.
        private var dismissals: [UUID: BrowserPromptDismissal] = [:]
        /// Each page this hosts, while its owner keeps it.
        private var hosted: [UUID: WeakNativePage] = [:]
        /// What waits for the binding to prepare each profile, by the
        /// preparation's identity.
        var preparations: [UUID: CheckedContinuation<Bool, Never>] = [:]
        private(set) var notifications: ChromiumProfileNotifications?
        /// The Chromium version a page's saved history belongs to: the running
        /// engine's, or before it starts, the version of the framework it
        /// loads, so the tabs a launch shows restore their history.
        var version: String? { host?.engineVersion() ?? Self.bundledVersion }

        // MARK: - Initializers

        init(
            host: any CrestMacShell, table: crest_engine_binding_t, fingerprint: [UInt8],
            pages: crest_engine_pages_t
        ) {
            self.host = host
            self.table = table
            self.fingerprint = fingerprint
            self.pages = NativeEnginePages(table: pages) { [weak self] presentation in
                guard let self else { return }
                presentation.present(on: self)
            }
        }

        init(runtime: ChromiumRuntime) {
            table = runtime.table
            fingerprint = CoreCodec.engineFingerprint
            pages = NativeEnginePages(
                start: { [weak runtime] in runtime?.requestStart() },
                present: { [weak self] presentation in
                    guard let self else { return }
                    presentation.present(on: self)
                })
        }

        func attach(host: any CrestMacShell, pages: crest_engine_pages_t) {
            precondition(self.host == nil, "Chromium's runtime attaches once per launch.")
            self.host = host
            self.pages.bind(pages)
        }

        // MARK: - Actions - Pages

        func host(_ page: CorePage) -> any EngineHostedPage {
            let native = ChromiumNativePage(id: page.id, engine: self)
            hold(native)
            return ChromiumPageAdapter(native)
        }

        // MARK: - Actions - Prompts

        /// Hears the questions `core` asks the person, which this engine's
        /// pages show. Its downloads' questions are the app's to answer.
        func follow(_ application: BrowserMacApplication) {
            let core = application.browser.core
            self.core = core
            notifications = ChromiumProfileNotifications(
                core: core, center: application.hostedNotificationCenter, pages: pages)
            core.followPrompts(self)
        }

        /// Sends the person's answer to a question the core asked.
        func answer(_ intent: some PromptIntent) {
            _ = try? core?.send(intent)
        }

        /// Whether the core hosts `pageID` on another engine.
        private func isAnotherEnginesPage(_ pageID: UUID) -> Bool {
            guard let engine = core?.state.pages[pageID]?.engine else { return false }
            return engine != .chromium
        }

        /// A new dismissal for a question a page shows.
        private func dismissal(for promptID: UUID) -> BrowserPromptDismissal {
            let dismissal = BrowserPromptDismissal()
            dismissals[promptID] = dismissal
            return dismissal
        }

        // MARK: - Actions - Links

        /// The app's own load of `url` in `pageID`, which the core resolves by
        /// the page's Space and asks the binding to run.
        func navigate(_ pageID: UUID, to url: URL) {
            _ = try? core?.send(Navigate(pageID: pageID, input: url.absoluteString))
        }

        /// Makes the link the binding staged as `stagedLinkID` in `sourcePageID`
        /// the first load of `pageID`, when it loads `url`. False when the core
        /// refuses it, such as for pages of another engine or profile.
        func stage(_ stagedLinkID: UUID, from sourcePageID: UUID, into pageID: UUID, expecting url: URL) -> Bool {
            guard let core else { return false }
            do {
                try core.send(
                    StageLink(
                        pageID: pageID, sourcePageID: sourcePageID, stagedLinkID: stagedLinkID,
                        url: url.absoluteString))
                return true
            } catch {
                return false
            }
        }

        // MARK: - Actions - Profiles

        /// Loads a Space's profile so its extensions can be listed before anything
        /// opens in it; answers whether it is ready.
        func prepareProfile(_ profileID: UUID) async -> Bool {
            if let runtime = ChromiumComposition.runtime, !(await runtime.whenReady()) { return false }
            guard !Task.isCancelled else { return false }
            let preparationID = UUID()
            return await withTaskCancellationHandler {
                await withCheckedContinuation { continuation in
                    guard !Task.isCancelled,
                        pages.request(PrepareProfile(profileID: profileID, preparationID: preparationID))
                    else {
                        continuation.resume(returning: false)
                        return
                    }
                    preparations[preparationID] = continuation
                }
            } onCancel: {
                Task { @MainActor [weak self] in
                    self?.preparations.removeValue(forKey: preparationID)?.resume(returning: false)
                }
            }
        }

        func icon(of pageID: UUID) -> Data? {
            guard host != nil else { return nil }
            return pages.request(PageIcon(pageID: pageID)).image
        }

        /// The live page the engine names with `id`, for requests that arrive
        /// with only a page identifier, such as a side panel's.
        func page(_ id: String) -> ChromiumNativePage? {
            UUID(uuidString: id).flatMap { hosted[$0]?.page }
        }

        /// The live page the core names `pageID`, for what the Mac shell asks
        /// of it, such as its context menu's rows.
        func page(_ pageID: UUID) -> ChromiumNativePage? {
            hosted[pageID]?.page
        }

        private func hold(_ native: ChromiumNativePage) {
            hosted = hosted.filter { $0.value.page != nil }
            hosted[native.pageID] = WeakNativePage(page: native)
        }

        /// The live page a presentation names. One for a page that is gone, or
        /// that its owner let go, changes nothing.
        func presentedPage(_ pageID: UUID) -> ChromiumNativePage? {
            guard let page = hosted[pageID]?.page, !page.disposed else { return nil }
            return page
        }
    }

    /// Shows a question the core asks on the page that asked it, and closes
    /// it once the core settles it. One no page of this engine can show any
    /// more is declined; one about a page another engine hosts is that
    /// engine's to show.
    extension ChromiumEngine: CorePromptHost {
        func ask(_ asked: ScriptDialogAsked) {
            guard let page = hosted[asked.pageID]?.page else {
                guard !isAnotherEnginesPage(asked.pageID) else { return }
                return answer(AnswerScriptDialog(promptID: asked.promptID, accepted: false, text: nil))
            }
            page.ask(asked, dismissal: dismissal(for: asked.promptID))
        }

        func ask(_ asked: AuthenticationAsked) {
            guard let page = hosted[asked.pageID]?.page else {
                guard !isAnotherEnginesPage(asked.pageID) else { return }
                return answer(AnswerAuthentication(promptID: asked.promptID, credential: nil))
            }
            page.ask(asked, dismissal: dismissal(for: asked.promptID))
        }

        func ask(_ asked: PermissionAsked) {
            guard let page = hosted[asked.pageID]?.page else {
                guard !isAnotherEnginesPage(asked.pageID) else { return }
                return answer(AnswerPermission(promptID: asked.promptID, grants: false, remembers: false))
            }
            page.ask(asked, dismissal: dismissal(for: asked.promptID))
        }

        func ask(_ asked: ExtensionInstallAsked) {
            ChromiumComposition.extensions.review(asked) { [weak self] accepted, withholds in
                self?.answer(
                    AnswerExtensionInstall(
                        promptID: asked.promptID, accepted: accepted, withholdsSiteAccess: withholds))
            }
        }

        /// The download prompts choose where a download goes.
        func ask(_ asked: DownloadDestinationAsked) {}

        /// The download prompts ask whether a download may go ahead.
        func ask(_ asked: DownloadApprovalAsked) {}

        /// The quit preparation asks about downloads in progress.
        func ask(_ asked: QuitWithDownloadsAsked) {}

        func dismiss(_ settled: PromptSettled) {
            dismissals.removeValue(forKey: settled.promptID)?.dismiss()
        }
    }

    /// A hosted page, held weakly so it goes with its owner.
    private struct WeakNativePage {
        weak var page: ChromiumNativePage?
    }

    /// The framework's entry point, which Chromium calls on its UI thread, the
    /// main thread, once it loads the framework: the Mac shell's host, the
    /// engine binding to register with the core the framework creates, and the
    /// pages' direct path to it. Public so a Release build, which hides
    /// internal symbols, still exports it for Chromium's lookup by name.
    @MainActor
    @_cdecl("crest_native_host_run")
    public func crestNativeHostRun() -> Int32 { ChromiumComposition.runNative() }

    @MainActor
    @_cdecl("crest_chromium_ui_start")
    public func crestChromiumUIStart(
        _ host: any CrestMacShell, _ binding: UnsafePointer<crest_engine_binding_t>,
        _ fingerprint: UnsafePointer<UInt8>, _ fingerprintLength: Int, _ pages: UnsafePointer<crest_engine_pages_t>
    ) {
        let contract = Array(UnsafeBufferPointer(start: fingerprint, count: fingerprintLength))
        host.attach(ui: ChromiumMacUI())
        ChromiumComposition.start(host: host, binding: binding.pointee, fingerprint: contract, pages: pages.pointee)
    }
#endif
