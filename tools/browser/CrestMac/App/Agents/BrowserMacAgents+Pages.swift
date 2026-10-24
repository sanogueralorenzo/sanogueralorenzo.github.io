import AppKit

/// What an agent may do with the page of a tab it uses: read it as an
/// outline, capture it, click, hover, fill, type, press keys and scroll, wait
/// for it, read its console and network activity, and, when the person lets
/// it, run scripts in the page's own world. A tab's page loads for the agent
/// without a window showing it, and keeps rendering while the agent uses it.
/// Calls on one tab run one at a time.
extension BrowserMacAgents {
    // MARK: - Types

    private struct ElementReference: Decodable {
        let tab: UUID
        let uid: String
    }

    private struct Capture: Decodable {
        enum CodingKeys: String, CodingKey {
            case tab, uid
            case fullPage = "full_page"
        }

        let tab: UUID
        let fullPage: Bool?
        let uid: String?
    }

    private struct Click: Decodable {
        enum Button: String, Decodable {
            case left, right, middle

            var pointer: PointerButton {
                switch self {
                case .left: .primary
                case .right: .secondary
                case .middle: .middle
                }
            }
        }

        let tab: UUID
        let uid: String
        let double: Bool?
        let button: Button?
    }

    private struct Fill: Decodable {
        let tab: UUID
        let uid: String
        let value: String
    }

    private struct Typing: Decodable {
        let tab: UUID
        let text: String
    }

    private struct KeyPress: Decodable {
        enum Modifier: String, Decodable {
            case shift = "Shift"
            case control = "Control"
            case option = "Option"
            case command = "Command"

            var keys: KeyModifiers {
                switch self {
                case .shift: .shift
                case .control: .control
                case .option: .option
                case .command: .command
                }
            }
        }

        let tab: UUID
        let key: String
        let modifiers: [Modifier]?
    }

    private struct Scrolling: Decodable {
        let tab: UUID
        let uid: String?
        let dx: Double?
        let dy: Double?
    }

    private struct Waiting: Decodable {
        enum CodingKeys: String, CodingKey {
            case tab, text, url
            case timeout = "timeout_ms"
        }

        let tab: UUID
        let text: String?
        let url: String?
        let timeout: Double?
    }

    private struct TextReading: Decodable {
        enum CodingKeys: String, CodingKey {
            case tab
            case limit = "max_chars"
        }

        let tab: UUID
        let limit: Int?
    }

    private struct PageText: Decodable {
        let url: String
        let title: String
        let text: String
        let truncated: Bool
    }

    private struct DialogAnswer: Decodable {
        let tab: UUID
        let accept: Bool
        let text: String?
    }

    private struct Since: Decodable {
        let tab: UUID
        let since: Int64?
    }

    private struct RequestReference: Decodable {
        let tab: UUID
        let id: Int64
    }

    private struct Script: Decodable {
        let tab: UUID
        let function: String
    }

    /// Where the element a uid names is in the viewport, in CSS pixels.
    private struct Located: Decodable {
        let x: Double
        let y: Double
        let left: Double
        let top: Double
        let width: Double
        let height: Double
        let tag: String
    }

    private struct Outline: Decodable {
        let url: String
        let title: String
        let outline: String
        let truncated: Bool
    }

    private struct ConsoleListing: Encodable {
        let sequence: Int64
        let level: String
        let text: String
        let source: String?
        let line: Int
    }

    /// A request as list_network_requests shows it. What the page's engine
    /// doesn't know, such as the method and status WebKit never reports, is
    /// left out rather than shown as empty.
    private struct RequestListing: Encodable {
        let id: Int64
        let url: String
        let method: String?
        let type: String
        let status: Int?
        let failure: String?

        init(_ request: PageNetworkRequest) {
            id = request.sequence
            url = request.url
            method = request.method.isEmpty ? nil : request.method
            type = request.resourceType
            status = request.status == 0 ? nil : request.status
            failure = request.failure
        }
    }

    /// A request as get_network_request shows it, its credentials hidden and,
    /// as in the listing, what the engine doesn't know left out.
    private struct RequestDetail: Encodable {
        /// Headers whose values carry the person's sign-ins, which an agent
        /// never reads.
        private static let privateHeaders: Set<String> = [
            "cookie", "set-cookie", "authorization", "proxy-authorization", "x-csrf-token", "x-xsrf-token",
            "x-api-key",
        ]

        let id: Int64
        let url: String
        let method: String?
        let type: String
        let status: Int?
        let mimeType: String?
        let requestHeaders: [String: String]?
        let responseHeaders: [String: String]?
        let durationMilliseconds: Double
        let bytes: Int64
        let failure: String?

        init(_ request: PageNetworkRequest) {
            let listing = RequestListing(request)
            id = listing.id
            url = listing.url
            method = listing.method
            type = listing.type
            status = listing.status
            mimeType = request.mimeType
            requestHeaders = Self.shown(request.requestHeaders)
            responseHeaders = Self.shown(request.responseHeaders)
            durationMilliseconds = request.duration
            bytes = request.bytes
            failure = request.failure
        }

        /// `headers` as an agent may read them, the person's sign-ins left
        /// out; nil when the engine reported none.
        private static func shown(_ headers: [PageHeader]) -> [String: String]? {
            guard !headers.isEmpty else { return nil }
            let shown = headers.map {
                ($0.name, privateHeaders.contains($0.name.lowercased()) ? "(hidden by Crest)" : $0.value)
            }
            return Dictionary(shown, uniquingKeysWith: { first, _ in first })
        }
    }

    // MARK: - Static Variables

    private static let scriptTimeout = Duration.seconds(15)
    private static let settleTimeout = Duration.seconds(15)
    private static let inputTimeout = Duration.seconds(10)
    /// How long after input a page is given for a load the input started to
    /// begin, as a click on a link or a submit button does.
    private static let loadGrace = Duration.seconds(1)
    private static let untrustedNote =
        "This page’s engine took the input as script events, which some pages ignore. If nothing changed, try another way."

    // MARK: - Actions - Reading

    func takeSnapshot(_ call: BrowserAgentCall) async throws(BrowserAgentFailure) -> AgentToolResult {
        let reference = try call.arguments(BrowserMacAgents.TabReference.self)
        return try await serially(on: reference.tab) { () async throws(BrowserAgentFailure) -> AgentToolResult in
            let page = try await self.settledPage(for: reference.tab, call)
            let outline = try await self.run(BrowserAgentPageScript.snapshot, on: page).decoded(Outline.self)
            var text = "Page: \(outline.title)\nAddress: \(outline.url)\n\n\(outline.outline)"
            if outline.truncated { text += "\n\n(The outline was cut short. Scroll or act on what is shown.)" }
            return .message(text)
        }
    }

    func readPageText(_ call: BrowserAgentCall) async throws(BrowserAgentFailure) -> AgentToolResult {
        let reading = try call.arguments(TextReading.self)
        let limit = reading.limit ?? 20_000
        guard (1_000...100_000).contains(limit) else {
            throw .invalidArguments("max_chars must be between 1000 and 100000.")
        }
        return try await serially(on: reading.tab) { () async throws(BrowserAgentFailure) -> AgentToolResult in
            let page = try await self.settledPage(for: reading.tab, call)
            let read = try await self.run(BrowserAgentPageScript.readText(limit: limit), on: page).decoded(
                PageText.self)
            var text = "Page: \(read.title)\nAddress: \(read.url)\n\n\(read.text)"
            if read.truncated { text += "\n\n(The text was cut short at \(limit) characters.)" }
            return .message(text)
        }
    }

    func screenshot(_ call: BrowserAgentCall) async throws(BrowserAgentFailure) -> AgentToolResult {
        let capture = try call.arguments(Capture.self)
        return try await serially(on: capture.tab) { () async throws(BrowserAgentFailure) -> AgentToolResult in
            let page = try await self.settledPage(for: capture.tab, call)
            let png: Data?
            if let uid = capture.uid {
                let located = try await self.locate(uid, on: page)
                png = await page.enginePage.capture(
                    area: CGRect(x: located.left, y: located.top, width: located.width, height: located.height))
            } else if capture.fullPage == true {
                png = try? await page.enginePage.export(.png)
            } else {
                png = await page.enginePage.capture()
            }
            guard let png, !png.isEmpty else { throw .refused("The page showed nothing to capture.") }
            // Base64 makes the image a third larger on its way to the agent.
            guard png.count / 3 * 4 < AgentLinkResponse.maximumBytes - (64 << 10) else { throw .tooLarge }
            return AgentToolResult(content: [.png(png)], isError: false)
        }
    }

    // MARK: - Actions - Input

    func click(_ call: BrowserAgentCall) async throws(BrowserAgentFailure) -> AgentToolResult {
        let click = try call.arguments(Click.self)
        return try await serially(on: click.tab) { () async throws(BrowserAgentFailure) -> AgentToolResult in
            let page = try await self.settledPage(for: click.tab, call)
            let located = try await self.locate(click.uid, on: page)
            let point = PagePoint(x: located.x, y: located.y)
            page.pointAgent(at: point, presses: true)
            let delivered = try await self.deliver(
                .click(at: point, button: click.button?.pointer ?? .primary, count: click.double == true ? 2 : 1),
                to: page, tab: click.tab, call)
            return .message(Self.done("Clicked the \(located.tag) \(click.uid).", delivered))
        }
    }

    func hover(_ call: BrowserAgentCall) async throws(BrowserAgentFailure) -> AgentToolResult {
        let reference = try call.arguments(ElementReference.self)
        return try await serially(on: reference.tab) { () async throws(BrowserAgentFailure) -> AgentToolResult in
            let page = try await self.settledPage(for: reference.tab, call)
            let located = try await self.locate(reference.uid, on: page)
            let point = PagePoint(x: located.x, y: located.y)
            page.pointAgent(at: point, presses: false)
            let delivered = try await self.deliver(.hover(at: point), to: page, tab: reference.tab, call)
            return .message(Self.done("The pointer is over the \(located.tag) \(reference.uid).", delivered))
        }
    }

    func fill(_ call: BrowserAgentCall) async throws(BrowserAgentFailure) -> AgentToolResult {
        let fill = try call.arguments(Fill.self)
        return try await serially(on: fill.tab) { () async throws(BrowserAgentFailure) -> AgentToolResult in
            let page = try await self.settledPage(for: fill.tab, call)
            // The pointer goes to the field first, as a person's would.
            if let located = try? await self.locate(fill.uid, on: page) {
                page.pointAgent(at: PagePoint(x: located.x, y: located.y), presses: true)
            }
            let prepared = try await self.run(BrowserAgentPageScript.prepareFill(fill.uid, value: fill.value), on: page)
            if let refusal = BrowserAgentFillRefusal.named(prepared["error"]?.string) {
                throw refusal.failure(uid: fill.uid, value: fill.value)
            }
            if let chosen = prepared["chosen"]?.string { return .message("Chose \(chosen).") }
            guard !fill.value.isEmpty else { return .message("Cleared \(fill.uid).") }
            let delivered = try await self.deliver(.type(fill.value), to: page, tab: fill.tab, call)
            return .message(Self.done("Filled \(fill.uid).", delivered))
        }
    }

    func typeText(_ call: BrowserAgentCall) async throws(BrowserAgentFailure) -> AgentToolResult {
        let typing = try call.arguments(Typing.self)
        return try await serially(on: typing.tab) { () async throws(BrowserAgentFailure) -> AgentToolResult in
            let page = try await self.settledPage(for: typing.tab, call)
            let delivered = try await self.deliver(.type(typing.text), to: page, tab: typing.tab, call)
            return .message(Self.done("Typed the text.", delivered))
        }
    }

    func pressKey(_ call: BrowserAgentCall) async throws(BrowserAgentFailure) -> AgentToolResult {
        let press = try call.arguments(KeyPress.self)
        guard let key = BrowserAgentKey.named(press.key) else {
            throw .invalidArguments(
                "\(press.key) is not a key Crest knows; use a KeyboardEvent key such as Enter or a.")
        }
        let modifiers = (press.modifiers ?? []).reduce(into: KeyModifiers()) { $0.formUnion($1.keys) }
        return try await serially(on: press.tab) { () async throws(BrowserAgentFailure) -> AgentToolResult in
            let page = try await self.settledPage(for: press.tab, call)
            let delivered = try await self.deliver(
                .press(key.pageKey, modifiers: modifiers), to: page, tab: press.tab, call)
            return .message(Self.done("Pressed \(press.key).", delivered))
        }
    }

    func scroll(_ call: BrowserAgentCall) async throws(BrowserAgentFailure) -> AgentToolResult {
        let scrolling = try call.arguments(Scrolling.self)
        return try await serially(on: scrolling.tab) { () async throws(BrowserAgentFailure) -> AgentToolResult in
            let page = try await self.settledPage(for: scrolling.tab, call)
            var point = PagePoint(x: 10, y: 10)
            if let uid = scrolling.uid {
                let located = try await self.locate(uid, on: page)
                point = PagePoint(x: located.x, y: located.y)
                page.pointAgent(at: point, presses: false)
            }
            let (dx, dy) = (scrolling.dx ?? 0, scrolling.dy ?? 0)
            guard dx != 0 || dy != 0 else { return .message("Scrolled \(scrolling.uid ?? "the page") into view.") }
            let delivered = try await self.deliver(
                .scroll(at: point, deltaX: dx, deltaY: dy), to: page, tab: scrolling.tab, call)
            return .message(Self.done("Scrolled.", delivered))
        }
    }

    func waitFor(_ call: BrowserAgentCall) async throws(BrowserAgentFailure) -> AgentToolResult {
        let waiting = try call.arguments(Waiting.self)
        guard waiting.text == nil || waiting.url == nil else { throw .invalidArguments("give text or url, not both.") }
        let timeout = Duration.milliseconds(Int(min(max(waiting.timeout ?? 10_000, 0), 60_000)))
        return try await serially(on: waiting.tab) { () async throws(BrowserAgentFailure) -> AgentToolResult in
            let page = try await self.settledPage(for: waiting.tab, call)
            let deadline = ContinuousClock.now + timeout
            repeat {
                if let address = waiting.url {
                    if page.live.url?.contains(address) == true {
                        return .message("The tab is at \(page.live.url ?? address).")
                    }
                } else if (try? await self.run(BrowserAgentPageScript.shows(waiting.text), on: page)) == .bool(true) {
                    return .message(waiting.text.map { "The page shows \($0)." } ?? "The page finished loading.")
                }
                try? await Task.sleep(for: .milliseconds(250))
            } while ContinuousClock.now < deadline
            if let address = waiting.url {
                throw .refused("The tab's address didn't come to contain \(address) in time.")
            }
            throw .timedOut
        }
    }

    // MARK: - Actions - Dialogs

    /// Answers the page's alert, confirm or prompt, never a question about
    /// leaving the page, which keeps the person's unsaved work theirs. It
    /// waits for no other call on the tab, since the dialog may be what holds
    /// one up.
    func handleDialog(_ call: BrowserAgentCall) async throws(BrowserAgentFailure) -> AgentToolResult {
        let answer = try call.arguments(DialogAnswer.self)
        let page = try page(for: answer.tab, call)
        guard let asked = page.scriptDialog, asked.question.kind != .beforeUnload else {
            throw .refused("The page shows no dialog an agent may answer.")
        }
        page.corePage.answer(AnswerScriptDialog(promptID: asked.promptID, accepted: answer.accept, text: answer.text))
        return .message(answer.accept ? "Accepted the page's dialog." : "Dismissed the page's dialog.")
    }

    // MARK: - Actions - Activity

    func listConsoleMessages(_ call: BrowserAgentCall) async throws(BrowserAgentFailure) -> AgentToolResult {
        let since = try call.arguments(Since.self)
        return try await serially(on: since.tab) { () async throws(BrowserAgentFailure) -> AgentToolResult in
            let page = try await self.settledPage(for: since.tab, call)
            let log = page.enginePage.console(after: since.since ?? 0)
            let messages = log.messages.map {
                ConsoleListing(
                    sequence: $0.sequence, level: String(describing: $0.level), text: $0.text, source: $0.source,
                    line: $0.line)
            }
            return .data(["messages": messages])
        }
    }

    func listNetworkRequests(_ call: BrowserAgentCall) async throws(BrowserAgentFailure) -> AgentToolResult {
        let since = try call.arguments(Since.self)
        return try await serially(on: since.tab) { () async throws(BrowserAgentFailure) -> AgentToolResult in
            let page = try await self.settledPage(for: since.tab, call)
            let log = page.enginePage.network(after: since.since ?? 0)
            let requests = log.requests.map(RequestListing.init)
            return .data(["requests": requests])
        }
    }

    func getNetworkRequest(_ call: BrowserAgentCall) async throws(BrowserAgentFailure) -> AgentToolResult {
        let reference = try call.arguments(RequestReference.self)
        return try await serially(on: reference.tab) { () async throws(BrowserAgentFailure) -> AgentToolResult in
            let page = try await self.settledPage(for: reference.tab, call)
            guard
                let request = page.enginePage.network(after: reference.id - 1).requests.first(where: {
                    $0.sequence == reference.id
                })
            else { throw .refused("The tab kept no request \(reference.id).") }
            return .data(RequestDetail(request))
        }
    }

    // MARK: - Actions - Scripts

    func evaluateScript(_ call: BrowserAgentCall) async throws(BrowserAgentFailure) -> AgentToolResult {
        let script = try call.arguments(Script.self)
        guard core.state.agentPreferences.runsScripts else { throw .scriptsOff }
        return try await serially(on: script.tab) { () async throws(BrowserAgentFailure) -> AgentToolResult in
            let page = try await self.settledPage(for: script.tab, call)
            guard
                let evaluated = await page.enginePage.evaluate(script.function, in: .page, timeout: Self.scriptTimeout)
            else { throw .timedOut }
            self.note(.ranScript, page.live.url ?? "", call)
            if let error = evaluated.error { throw .script(error) }
            return .message(evaluated.json ?? "null")
        }
    }

    // MARK: - Actions - Pages

    /// The live page of tab `tabID`, which the agent uses from now on, loaded
    /// and rendering for it whether or not a window shows it. Its console and
    /// network are kept from the agent's first use of it, so a tab the agent
    /// opens is kept from its first load.
    func page(for tabID: UUID, _ call: BrowserAgentCall) throws(BrowserAgentFailure) -> BrowserPage {
        let (space, tab) = try claim(tabID, call)
        guard let page = application.pages.agentPage(for: tab, in: space) else { throw .noPage }
        guard Self.showsWebPage(page.live.url) else { throw .notWebPage }
        if call.link.observedPages[tabID] != page.enginePage.id, page.enginePage.observeActivity(true) {
            call.link.observedPages[tabID] = page.enginePage.id
        }
        return page
    }

    /// The live page of tab `tabID`, as `page(for:)` gives it, once it shows a
    /// document: one that was just loaded for the agent, or is still on its
    /// way, settles first, for up to `settleTimeout`. Just after the agent's
    /// input, a load the input starts is waited for too.
    private func settledPage(for tabID: UUID, _ call: BrowserAgentCall) async throws(BrowserAgentFailure) -> BrowserPage
    {
        let page = try page(for: tabID, call)
        if let input = call.link.lastInput.removeValue(forKey: tabID) {
            while !page.live.isLoading, page.live.pendingURL == nil, ContinuousClock.now < input + Self.loadGrace {
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
        let deadline = ContinuousClock.now + Self.settleTimeout
        while page.committedNavigationCount == 0 || page.live.isLoading || page.live.pendingURL != nil,
            ContinuousClock.now < deadline
        {
            try? await Task.sleep(for: .milliseconds(100))
        }
        // The page renders for the agent from now on, at the size of the window
        // over its Space, once its engine made it; a page still being made is
        // asked again on the agent's next call.
        // A load may have left the web for a page agents can't use.
        guard Self.showsWebPage(page.live.url) else { throw .notWebPage }
        if call.link.heldPages[tabID] != page.enginePage.id {
            let size =
                frontWindow(over: try claim(tabID, call).0)?.pages.presentationWindow?.contentLayoutRect.size
                ?? CGSize(width: 1280, height: 800)
            if page.enginePage.holdRendering(true, size: size) {
                call.link.heldPages[tabID] = page.enginePage.id
                // A page that took a size lays out again before it is read.
                try? await Task.sleep(for: .milliseconds(150))
            }
        }
        return page
    }

    /// Whether `address` shows a web page, or a blank one or none yet, which
    /// an agent may use, rather than one of the browser's own, an extension's
    /// or a file.
    private static func showsWebPage(_ address: String?) -> Bool {
        guard let address else { return true }
        guard address != "about:blank" else { return true }
        let scheme = URL(string: address)?.scheme?.lowercased()
        return scheme == "http" || scheme == "https"
    }

    /// What `script` answered in the agent's world of `page`.
    private func run(_ script: BrowserAgentPageScript, on page: BrowserPage) async throws(BrowserAgentFailure)
        -> AgentJSON
    {
        guard let evaluated = await page.enginePage.evaluate(script.source, in: .agent, timeout: Self.scriptTimeout)
        else {
            throw page.scriptDialog.map(BrowserAgentFailure.dialog) ?? .timedOut
        }
        if let error = evaluated.error { throw .script(error) }
        guard let json = evaluated.json, let value = try? JSONDecoder().decode(AgentJSON.self, from: Data(json.utf8))
        else {
            return .null
        }
        return value
    }

    private func locate(_ uid: String, on page: BrowserPage) async throws(BrowserAgentFailure) -> Located {
        let answer = try await run(BrowserAgentPageScript.locate(uid), on: page)
        guard answer["error"] == nil, let located = try? answer.decoded(as: Located.self) else {
            throw .unknownElement(uid)
        }
        return located
    }

    /// Delivers `input` to `page` of tab `tabID`, which the agent's next call
    /// on the tab gives a moment to start a load.
    private func deliver(_ input: EnginePageInput, to page: BrowserPage, tab tabID: UUID, _ call: BrowserAgentCall)
        async throws(BrowserAgentFailure) -> PageInputDelivered
    {
        guard let delivered = await page.enginePage.deliver(input, timeout: Self.inputTimeout), delivered.delivered
        else {
            // Input that opens a dialog waits on its answer.
            throw page.scriptDialog.map(BrowserAgentFailure.dialog) ?? .refused("The page did not take the input.")
        }
        call.link.lastInput[tabID] = .now
        return delivered
    }

    private static func done(_ message: String, _ delivered: PageInputDelivered) -> String {
        delivered.trusted ? message : "\(message) \(untrustedNote)"
    }
}

extension AgentJSON {
    /// The value read as `Value`, or the failure that says the page answered
    /// something else.
    fileprivate func decoded<Value: Decodable>(_: Value.Type) throws(BrowserAgentFailure) -> Value {
        guard let value = try? decoded(as: Value.self) else {
            throw .refused("The page answered something Crest can’t read.")
        }
        return value
    }
}

extension EnginePage {
    /// What the page's view shows now, all of it or `area`, as a PNG.
    fileprivate func capture(area: CGRect? = nil) async -> Data? {
        await withCheckedContinuation { continuation in
            capture(area: area) { continuation.resume(returning: $0) }
        }
    }
}
