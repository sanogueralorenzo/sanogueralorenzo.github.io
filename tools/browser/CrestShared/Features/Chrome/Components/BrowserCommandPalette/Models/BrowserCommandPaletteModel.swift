import Foundation
import Observation
import SwiftUI

/// The shared palette's rows, keyboard selection and the search provider or
/// scope a person narrowed it to. The core ranks what the palette offers for each
/// query, off the main thread; an answer that arrives after a newer keystroke
/// is dropped, so the latest query always wins, and a key pressed before the
/// first answer for its text waits for it. The query text, the selection, the
/// completion editing and the modifier keys held stay here.
@MainActor
@Observable
final class BrowserCommandPaletteModel {
    // MARK: - Static Variables

    /// How long Return, Tab or Down wait for the answer to what was typed
    /// before they act on the rows already shown.
    private static let keyWait: Duration = .milliseconds(300)

    // MARK: - Variables

    /// The window the palette speaks for, whose core answers it.
    let browser: BrowserStore
    /// The Space the palette speaks for, or nil when the window shows none.
    let space: SpaceModel?
    let selectedTabID: UUID?
    let commands: BrowserCommandPaletteCommandRegistry?
    /// Whether the palette offers the platform's resting commands before
    /// anything is typed. The Start Page's palette offers commands only once
    /// what is typed matches one.
    let offersRestingCommands: Bool

    var query: String {
        didSet {
            guard query != oldValue else { return }
            selectedResultIndex = 0
            requestAnswer()
        }
    }

    private(set) var groups: [BrowserCommandPaletteGroup] = []
    /// Every row, in the order the keyboard steps through them.
    private(set) var items: [BrowserCommandPaletteItem] = []
    private(set) var selectedResultIndex = 0
    private(set) var keyboardSelectionRevision = 0
    private(set) var completionEditing = BrowserURLCompletionEditingState()
    /// The search provider the person narrowed the palette to, or nil.
    private(set) var activeProvider: SearchProvider?
    /// The kind of result the person narrowed the palette to, or nil.
    private(set) var activeScope: PaletteScope?
    /// The modifier keys the person holds, which choose where a row opens.
    private(set) var heldModifiers: EventModifiers = []
    private var completionProposal: AddressCompletion?
    private var offeredSearch: SearchOffer?
    /// Every provider what is typed names or starts to name, closest first.
    private var matchingProviders: [SearchProvider] = []
    private var offeredScope: PaletteScope?
    @ObservationIgnored var applyCompletion: ((String, NSRange) -> Void)?
    /// Replaces the field's text, as entering or leaving a scope does.
    @ObservationIgnored var replaceText: ((String) -> Void)?

    /// Counts keystrokes: each query asks under the next number, and only the
    /// answer to the latest is shown.
    @ObservationIgnored private var sequence = 0
    /// The keystroke whose answer the rows show.
    @ObservationIgnored private var shownSequence = 0
    @ObservationIgnored private var answerTask: Task<Void, Never>?
    /// A key pressed before the answer to what was typed arrived, and the
    /// wait that runs it on the rows already shown.
    @ObservationIgnored private var waitingKey: (() -> Void)?
    @ObservationIgnored private var keyWaitTask: Task<Void, Never>?
    /// The text on the pasteboard when the palette opened, offered with
    /// Paste and Go while the text is still what the palette opened with, or
    /// nil.
    @ObservationIgnored private let pasteboard: String?
    /// What the field held when the palette opened: nothing for a new tab, or
    /// the address of the page the window shows.
    @ObservationIgnored private let openedWith: String

    private let suggestionDebounce: Duration
    private let fetchSuggestions: @Sendable (URL) async throws -> [String]
    private let isSourceAvailableAction: (BrowserTabRuntimeAssignment) -> Bool
    private let selectTabAction: (BrowserTabRuntimeAssignment, BrowserTabRuntimeAssignment) -> Bool
    private let openURLAction: (BrowserTabRuntimeAssignment, URL, BrowserCommandPaletteOpening) -> Bool
    private let dismissAction: () -> Void
    private let emptySelectionActions: BrowserEmptySelectionPaletteActions?
    /// Where this platform can open a row, which the modifier keys choose among.
    let openings: [BrowserCommandPaletteOpening]

    /// How the person set the palette to rank and arrange its rows.
    var preferences: PalettePreferences { BrowserAppPreferenceStore.shared.preferences.palette }

    /// The search provider Tab enters for what is typed, or nil: one the
    /// text names exactly by its shortcut even while a completion shows, else
    /// one it names by title or site once no completion does.
    var providerOffer: SearchProvider? {
        guard isUnscoped, completionEditing.isAtEnd, preferences.searchesSitesWithTab, isCompletionSourceAvailable,
            let offer = offeredSearch, urlCompletion == nil || offer.beatsCompletion
        else { return nil }
        return offer.provider
    }

    /// The providers the palette offers as chips while what is typed is one
    /// word, closest first; none once the palette is narrowed.
    var providerChips: [SearchProvider] {
        guard isUnscoped, preferences.searchesSitesWithTab, isCompletionSourceAvailable else { return [] }
        return matchingProviders
    }

    /// The scope Tab enters for what is typed, or nil.
    var scopeOffer: PaletteScope? {
        guard isUnscoped, completionEditing.isAtEnd, urlCompletion == nil else { return nil }
        return offeredScope
    }

    var urlCompletion: AddressCompletion? {
        guard isUnscoped, isCompletionSourceAvailable, completionEditing.canPropose(for: query),
            completionProposal?.typed == query
        else { return nil }
        return completionProposal
    }

    var isCompletionSourceAvailable: Bool {
        if selectedTabID != nil { return availableSourceAssignment != nil }
        guard let space, let actions = emptySelectionActions,
            actions.source == BrowserSpaceRuntimeAssignment(spaceID: space.id, profileID: space.profileID)
        else { return false }
        return actions.isAvailable
    }

    /// Where Return opens the selected row while the person holds the keys
    /// they hold: `here` for a row that opens nothing, or keys that choose
    /// nothing.
    var selectedOpening: BrowserCommandPaletteOpening {
        guard items.indices.contains(selectedResultIndex) else { return .here }
        return opening(for: items[selectedResultIndex].row)
    }

    private var isUnscoped: Bool { activeProvider == nil && activeScope == nil }

    private var availableSourceAssignment: BrowserTabRuntimeAssignment? {
        guard let sourceAssignment, isSourceAvailableAction(sourceAssignment) else { return nil }
        return sourceAssignment
    }

    private var sourceAssignment: BrowserTabRuntimeAssignment? {
        guard let space, let selectedTabID else { return nil }
        return BrowserTabRuntimeAssignment(tabID: selectedTabID, spaceID: space.id, profileID: space.profileID)
    }

    // MARK: - Initializers

    init(
        browser: BrowserStore,
        space: SpaceModel?,
        selectedTabID: UUID?,
        initialQuery: String,
        commands: BrowserCommandPaletteCommandRegistry?,
        offersRestingCommands: Bool = true,
        suggestionDebounce: Duration = .milliseconds(250),
        fetchSuggestions: @escaping @Sendable (URL) async throws -> [String] = { address in
            try await BrowserSearchSuggestionClient.shared.suggestions(from: address)
        },
        isSourceAvailable: @escaping (BrowserTabRuntimeAssignment) -> Bool,
        selectTab: @escaping (BrowserTabRuntimeAssignment, BrowserTabRuntimeAssignment) -> Bool,
        openURL: @escaping (BrowserTabRuntimeAssignment, URL, BrowserCommandPaletteOpening) -> Bool,
        dismiss: @escaping () -> Void,
        emptySelectionActions: BrowserEmptySelectionPaletteActions? = nil,
        openings: [BrowserCommandPaletteOpening] = [.here],
        readPasteboard: () -> String? = { nil }
    ) {
        self.browser = browser
        self.space = space
        self.selectedTabID = selectedTabID
        self.commands = commands
        self.offersRestingCommands = offersRestingCommands
        query = initialQuery
        self.suggestionDebounce = suggestionDebounce
        self.fetchSuggestions = fetchSuggestions
        isSourceAvailableAction = isSourceAvailable
        selectTabAction = selectTab
        openURLAction = openURL
        dismissAction = dismiss
        self.emptySelectionActions = emptySelectionActions
        self.openings = openings
        openedWith = initialQuery
        pasteboard = BrowserAppPreferenceStore.shared.preferences.palette.offers(.pasteAndGo) ? readPasteboard() : nil
        // The palette opens with its rows: the resting answer is quick to
        // rank, so it is asked for on the main thread.
        if let answer = try? browser.core.query(question(for: initialQuery)) { show(answer, for: sequence) }
    }

    // MARK: - Actions - Completion

    func updateCompletionEditing(text: String, selection: NSRange, isComposing: Bool) {
        let couldPropose = completionEditing.canPropose(for: query)
        completionEditing.update(text: text, selection: selection, isComposing: isComposing)
        if !isComposing { query = text }
        // The core leads with the completion only while the field may show
        // it, so a caret that moves away asks again.
        if !isComposing, text == query, couldPropose != completionEditing.canPropose(for: query) { requestAnswer() }
    }

    func rejectURLCompletion() { completionEditing.reject() }

    func invalidateURLCompletion() {
        completionProposal = nil
        completionEditing.reject()
    }

    @discardableResult
    func acceptURLCompletion() -> Bool {
        guard let proposal = urlCompletion, let applyCompletion else { return false }
        completionEditing.reject()
        applyCompletion(proposal.insertionText, proposal.insertionRange)
        // Return right after Tab must find the accepted address as the primary
        // action even before the off-main answer arrives.
        if query == proposal.accepted, let answer = try? browser.core.query(question(for: query)) {
            show(answer, for: sequence)
            selectedResultIndex = 0
        }
        completionEditing.reject()
        return true
    }

    // MARK: - Actions - Keys

    /// Tab: enters the search provider whose shortcut the text is, else
    /// accepts the completion the field shows, else enters the provider or
    /// scope the text names, else moves to the next row. It never moves focus
    /// out of the field.
    func pressTab() {
        waitForAnswer { [weak self] in
            guard let self else { return }
            if let provider = providerOffer {
                enter(provider)
                return
            }
            if acceptURLCompletion() { return }
            if let scope = scopeOffer {
                enter(scope)
            } else {
                moveSelection(by: 1)
            }
        }
    }

    /// Shift-Tab moves to the row before.
    func pressBacktab() { moveSelection(by: -1) }

    /// Return runs the selected row, once the answer to what was typed arrived.
    func pressReturn() {
        waitForAnswer { [weak self] in self?.activateSelectedResult() }
    }

    /// Down moves to the next row, once the answer to what was typed arrived.
    func pressDown() {
        waitForAnswer { [weak self] in self?.moveSelection(by: 1) }
    }

    /// Notes the modifier keys the person holds.
    func updateHeldModifiers(_ modifiers: EventModifiers) {
        let held = modifiers.intersection([.command, .shift, .option])
        if held != heldModifiers { heldModifiers = held }
    }

    /// Runs `key` now when the rows answer what was typed, or once they do,
    /// or after a short wait on the rows already shown.
    private func waitForAnswer(_ key: @escaping () -> Void) {
        guard shownSequence != sequence else {
            key()
            return
        }
        waitingKey = key
        keyWaitTask?.cancel()
        keyWaitTask = Task { [weak self] in
            try? await Task.sleep(for: Self.keyWait)
            guard !Task.isCancelled, let self else { return }
            runWaitingKey()
        }
    }

    private func runWaitingKey() {
        keyWaitTask?.cancel()
        guard let key = waitingKey else { return }
        waitingKey = nil
        // A key that waited too long acts on what is shown, whatever it answers.
        shownSequence = sequence
        key()
    }

    // MARK: - Actions - Scopes

    /// Narrows the palette to `provider`: what the person types next searches it.
    func enter(_ provider: SearchProvider) {
        activeProvider = provider
        activeScope = nil
        narrowed()
    }

    /// Narrows the palette to `scope`'s kind of result.
    func enter(_ scope: PaletteScope) {
        activeScope = scope
        activeProvider = nil
        narrowed()
    }

    /// Leaves the search provider or scope, keeping what was typed.
    @discardableResult
    func leaveScope() -> Bool {
        guard !isUnscoped else { return false }
        activeProvider = nil
        activeScope = nil
        requestAnswer()
        replaceText?(query)
        return true
    }

    /// Enters what the text named in the palette's notation, keeping what
    /// followed it as what is typed.
    private func enter(_ entry: PaletteEntry) {
        activeProvider = entry.provider
        activeScope = entry.scope
        narrowed(keeping: entry.text)
    }

    private func narrowed(keeping text: String = "") {
        invalidateURLCompletion()
        query = text
        replaceText?(text)
        requestAnswer()
    }

    // MARK: - Actions - Selection

    func moveSelection(by offset: Int) {
        rejectURLCompletion()
        guard shownSequence == sequence, !items.isEmpty else { return }
        selectedResultIndex = (selectedResultIndex + offset + items.count) % items.count
        keyboardSelectionRevision &+= 1
    }

    /// Moves to the first row of the next or previous section.
    func moveSection(by offset: Int) {
        rejectURLCompletion()
        guard shownSequence == sequence, !groups.isEmpty,
            let current = groups.firstIndex(where: { $0.items.contains { $0.index == selectedResultIndex } }),
            let first = groups[(current + offset + groups.count) % groups.count].items.first
        else { return }
        selectedResultIndex = first.index
        keyboardSelectionRevision &+= 1
    }

    func selectResult(at index: Int) {
        rejectURLCompletion()
        guard shownSequence == sequence, items.indices.contains(index) else { return }
        selectedResultIndex = index
    }

    /// Forgets the row the person moved to: a row whose kind forgets from
    /// history takes its page out of the Space's history, and what the palette
    /// learned about the row goes. The row the palette leads with is never
    /// forgotten this way.
    @discardableResult
    func forgetSelectedRow() -> Bool {
        guard selectedResultIndex > 0, items.indices.contains(selectedResultIndex) else { return false }
        let row = items[selectedResultIndex].row
        guard row.kind.forgetsFromHistory || row.reason == .learned else { return false }
        if row.kind.forgetsFromHistory, let address = row.address, let space {
            browser.removeHistoryAddress(address, in: space.id)
        }
        try? browser.core.send(ForgetPaletteChoices(windowID: browser.windowID, row: row.seed))
        requestAnswer()
        return true
    }

    func activateSelectedResult() {
        guard items.indices.contains(selectedResultIndex) else { return }
        activate(items[selectedResultIndex].row)
    }

    /// Runs `row` as its kind's activation does. One that closes the palette
    /// has it remember the pick for what was typed and close; one that
    /// narrows it, to a provider or a scope, leaves it open.
    func activate(_ row: PaletteRow) {
        guard shownSequence == sequence else { return }
        let activation = row.kind.activation
        let typed = query
        guard BrowserCommandPaletteActivation.of(activation)?.run(row, self) == true, activation.closesPalette else {
            return
        }
        try? browser.core.send(RecordPaletteChoice(windowID: browser.windowID, text: typed, row: row.seed))
        dismiss()
    }

    func dismiss() {
        dismissAction()
    }

    func waitForPendingResults() async {
        await answerTask?.value
    }

    // MARK: - Actions - Activation

    /// Shows the tab `tabID` names in the palette's Space, from the tab the
    /// palette opened over or from the window's New Tab surface.
    func switchToTab(_ tabID: UUID?) -> Bool {
        guard let tabID else { return false }
        if selectedTabID == nil {
            guard let actions = availableEmptySelectionActions, let space else { return false }
            return actions.selectTab(
                BrowserTabRuntimeAssignment(tabID: tabID, spaceID: space.id, profileID: space.profileID))
        }
        guard let sourceAssignment = availableSourceAssignment else { return false }
        return selectTabAction(
            sourceAssignment,
            BrowserTabRuntimeAssignment(
                tabID: tabID, spaceID: sourceAssignment.spaceID, profileID: sourceAssignment.profileID))
    }

    /// Opens `address` where `opening` says, from the tab the palette opened
    /// over, or in the window's New Tab surface, which opens it in place.
    func open(_ address: String?, where opening: BrowserCommandPaletteOpening) -> Bool {
        guard let url = address.flatMap(URL.init(string:)) else { return false }
        if selectedTabID == nil { return availableEmptySelectionActions?.openURL(url) ?? false }
        guard let sourceAssignment = availableSourceAssignment else { return false }
        return openURLAction(sourceAssignment, url, opening)
    }

    /// Where `row` opens while the person holds the keys they hold: where the
    /// keys choose for a row whose activation lets them, else here.
    func opening(for row: PaletteRow) -> BrowserCommandPaletteOpening {
        row.kind.activation.opensWhereKeysChoose
            ? BrowserCommandPaletteOpening.held(heldModifiers, among: openings) : .here
    }

    /// The New Tab surface's actions, when the palette opened over it in the
    /// Space it shows and it can act now.
    private var availableEmptySelectionActions: BrowserEmptySelectionPaletteActions? {
        guard let actions = emptySelectionActions, let space,
            actions.source == BrowserSpaceRuntimeAssignment(spaceID: space.id, profileID: space.profileID),
            actions.isAvailable
        else { return nil }
        return actions
    }

    // MARK: - Actions - Presentation

    /// The tab a row shows, for its icon.
    func tab(for row: PaletteRow) -> TabStateModel? {
        row.tabID.flatMap { space?.tabs.model($0) }
    }

    /// The engine a row's tab runs on, when its icon wears that engine's
    /// badge, for what the row says to VoiceOver.
    func engineBadge(for row: PaletteRow) -> EngineKind? {
        row.tabID.flatMap(browser.core.state.engineBadge(forTab:))
    }

    /// The search provider a row searches with, for its icon.
    func searchProvider(for row: PaletteRow) -> SearchProvider? {
        row.provider
    }

    // MARK: - Actions - Answers

    /// The question for `text`, with the commands and settings pages this
    /// window offers, the suggestions fetched for the same text, the scope
    /// the person narrowed to, and whether the field may complete inline.
    private func question(for text: String, remote: [String] = []) -> PaletteSuggestions {
        PaletteSuggestions(
            windowID: browser.windowID, text: text, commands: offeredCommands(for: text),
            settingsPages: commands?.settingsPages ?? [], remote: remote, provider: activeProvider?.seed,
            scope: activeScope, allowsCompletion: completionEditing.canPropose(for: text),
            pasteboard: text.isEmpty || text == openedWith ? pasteboard : nil)
    }

    /// The commands the core may rank for `text`. A palette without resting
    /// commands offers none while the text is blank, which the core reads as
    /// nothing typed.
    private func offeredCommands(for text: String) -> [PaletteCommand] {
        guard offersRestingCommands || !text.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }
        return commands?.paletteCommands ?? []
    }

    /// Asks the core for the current query's answer off the main thread, then
    /// for the search suggestions the answer allows, and shows each only while
    /// no later keystroke has asked again.
    private func requestAnswer() {
        sequence &+= 1
        let asked = sequence
        let question = question(for: query)
        let core = browser.core
        answerTask?.cancel()
        answerTask = Task { [weak self] in
            guard let answer = await Self.answer(question, from: core), !Task.isCancelled, let self,
                asked == sequence
            else { return }
            show(answer, for: asked)
            guard let address = answer.suggestionAddress.flatMap(URL.init(string:)) else { return }
            do {
                try await Task.sleep(for: suggestionDebounce)
                let fetched = try await fetchSuggestions(address)
                try Task.checkCancellation()
                guard asked == sequence, !fetched.isEmpty,
                    let merged = await Self.answer(
                        PaletteSuggestions(
                            windowID: question.windowID, text: question.text, commands: question.commands,
                            settingsPages: question.settingsPages, remote: fetched, provider: question.provider,
                            scope: question.scope, allowsCompletion: question.allowsCompletion,
                            pasteboard: question.pasteboard),
                        from: core),
                    asked == sequence
                else { return }
                let selected = items.indices.contains(selectedResultIndex) ? items[selectedResultIndex].id : nil
                show(merged, for: asked)
                if let selected, let index = items.firstIndex(where: { $0.id == selected }) {
                    selectedResultIndex = index
                }
            } catch {
                // The local rows are already shown. Cancellation, a failed
                // fetch or an unreadable response leave them as they are.
            }
        }
    }

    private func show(_ answer: PaletteAnswer, for asked: Int) {
        shownSequence = asked
        groups = BrowserCommandPaletteGroup.groups(of: answer)
        items = groups.flatMap(\.items)
        completionProposal = answer.completion
        offeredSearch = answer.offeredSearch
        matchingProviders = answer.matchingProviders
        offeredScope = answer.offeredScope
        if !items.indices.contains(selectedResultIndex) { selectedResultIndex = 0 }
        // A key waiting on this answer acts once the entry's own answer arrives.
        if asked == sequence, isUnscoped, let entry = answer.entry { enter(entry) }
        if asked == sequence, waitingKey != nil { runWaitingKey() }
    }

    /// The core's answer, ranked on a background thread.
    private nonisolated static func answer(_ question: PaletteSuggestions, from core: CrestCore) async -> PaletteAnswer?
    {
        await Task.detached(priority: .userInitiated) { try? core.query(question) }.value
    }
}

extension PalettePreferences {
    /// Whether the palette offers results of `source`.
    func offers(_ source: PaletteSource) -> Bool {
        sources.first { $0.source == source }?.isEnabled ?? false
    }
}

enum BrowserSearchSuggestionResponseParser {
    static func suggestions(from data: Data) -> [String] {
        guard data.count <= BrowserSearchSuggestionClient.maximumResponseByteCount else {
            return []
        }
        guard
            let payload = try? JSONSerialization.jsonObject(with: data) as? [Any],
            payload.count >= 2,
            let values = payload[1] as? [Any]
        else { return [] }
        return values.compactMap { $0 as? String }.prefix(20).map { $0 }
    }
}

/// Fetches an engine's search suggestions from the address the core names,
/// without cookies or caching.
actor BrowserSearchSuggestionClient {
    static let shared = BrowserSearchSuggestionClient()
    static let maximumResponseByteCount = 64 * 1_024

    nonisolated static var sessionConfiguration: URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 5
        configuration.timeoutIntervalForResource = 5
        return configuration
    }

    private let session: URLSession

    init(session: URLSession? = nil) {
        self.session = session ?? URLSession(configuration: Self.sessionConfiguration)
    }

    func suggestions(from address: URL) async throws -> [String] {
        var request = URLRequest(url: address)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (bytes, response) = try await session.bytes(for: request)
        guard
            let response = response as? HTTPURLResponse,
            (200...299).contains(response.statusCode),
            response.expectedContentLength <= 0
                || response.expectedContentLength <= Self.maximumResponseByteCount
        else { return [] }

        var data = Data()
        data.reserveCapacity(min(Self.maximumResponseByteCount, 8 * 1_024))
        for try await byte in bytes {
            guard data.count < Self.maximumResponseByteCount else { return [] }
            data.append(byte)
        }
        return BrowserSearchSuggestionResponseParser.suggestions(from: data)
    }
}
