#if CREST_CHROMIUM_HOST
    import AppKit
    import CrestCoreABI

    /// Keeps the core's registration stable while Chromium is unloaded. The
    /// first command starts its runtime, then attaches the real C++ binding to
    /// the same core handle and delivers the commands in their original order.
    @MainActor
    final class ChromiumRuntime: NativeEngineBinding {
        // MARK: - Variables

        let integration = BrowserEngineRegistration.chromium
        let fingerprint = CoreCodec.engineFingerprint
        private(set) lazy var engine = ChromiumEngine(runtime: self)
        private var binding: crest_engine_binding_t?
        private var commands: [[UInt8]] = []
        private var waiting: [UUID: CheckedContinuation<Bool, Never>] = [:]
        private var app: UInt64 = 0
        private var engineID: UInt64 = 0
        private var report: crest_engine_report_t?
        private var ask: crest_engine_ask_t?
        private(set) var startRequested = false

        var table: crest_engine_binding_t {
            crest_engine_binding_t(
                context: Unmanaged.passUnretained(self).toOpaque(),
                attach: attachDeferredChromium, run: runDeferredChromium)
        }

        // MARK: - Actions - Registration

        fileprivate func attach(app: UInt64, engine: UInt64, report: crest_engine_report_t?, ask: crest_engine_ask_t?) {
            self.app = app
            engineID = engine
            self.report = report
            self.ask = ask
        }

        func bind(
            host: any CrestMacShell, binding: crest_engine_binding_t, fingerprint: [UInt8], pages: crest_engine_pages_t
        ) {
            precondition(self.binding == nil, "Chromium starts once per launch.")
            precondition(fingerprint == self.fingerprint, "Rebuild Chromium against this engine contract.")
            self.binding = binding
            engine.attach(host: host, pages: pages)
            binding.attach?(binding.context, app, engineID, report, ask)
            let queued = commands
            commands = []
            for command in queued { run(command) }
            engine.pages.replayStartingRequests()
            let completions = waiting
            waiting = [:]
            for completion in completions.values { completion.resume(returning: true) }
        }

        // MARK: - Actions - Runtime

        /// Ends the native launch loop. The launcher then enters Chromium's
        /// normal browser loop, keeping Crest's application and delegate.
        func requestStart() {
            guard binding == nil, !startRequested else { return }
            startRequested = true
            DispatchQueue.main.async {
                NSApp.stop(nil)
                if let event = NSEvent.otherEvent(
                    with: .applicationDefined, location: .zero, modifierFlags: [], timestamp: 0,
                    windowNumber: 0, context: nil, subtype: 0, data1: 0, data2: 0)
                {
                    NSApp.postEvent(event, atStart: false)
                }
            }
        }

        func whenReady() async -> Bool {
            guard !Task.isCancelled else { return false }
            guard binding == nil else { return true }
            let requestID = UUID()
            return await withTaskCancellationHandler {
                await withCheckedContinuation { continuation in
                    guard !Task.isCancelled else {
                        continuation.resume(returning: false)
                        return
                    }
                    waiting[requestID] = continuation
                    requestStart()
                }
            } onCancel: {
                Task { @MainActor [weak self] in
                    self?.waiting.removeValue(forKey: requestID)?.resume(returning: false)
                }
            }
        }

        fileprivate func run(_ bytes: [UInt8]) {
            guard let binding else {
                commands.append(bytes)
                requestStart()
                return
            }
            bytes.withUnsafeBufferPointer { binding.run?(binding.context, $0.baseAddress, $0.count) }
        }

        // MARK: - Actions - Pages

        func host(_ page: CorePage) -> any EngineHostedPage { engine.host(page) }
        func icon(of pageID: UUID) -> Data? { engine.icon(of: pageID) }
    }

    private func attachDeferredChromium(
        _ context: UnsafeMutableRawPointer?, _ app: UInt64, _ engine: UInt64,
        _ report: crest_engine_report_t?, _ ask: crest_engine_ask_t?
    ) {
        guard let context else { return }
        let runtime = Unmanaged<ChromiumRuntime>.fromOpaque(context).takeUnretainedValue()
        MainActor.assumeIsolated { runtime.attach(app: app, engine: engine, report: report, ask: ask) }
    }

    private func runDeferredChromium(_ context: UnsafeMutableRawPointer?, _ bytes: UnsafePointer<UInt8>?, _ length: Int)
    {
        guard let context else { return }
        let runtime = Unmanaged<ChromiumRuntime>.fromOpaque(context).takeUnretainedValue()
        let command = bytes.map { Array(UnsafeBufferPointer(start: $0, count: length)) } ?? []
        MainActor.assumeIsolated { runtime.run(command) }
    }
#endif
