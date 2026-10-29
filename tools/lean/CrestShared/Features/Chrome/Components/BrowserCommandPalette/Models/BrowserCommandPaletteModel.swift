import Foundation
import Observation
import SwiftUI

/// The shared palette's rows, keyboard selection and the local
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
    /// The kind of result the person narrowed the palette to, or nil.
    private(set) var activeScope: PaletteScope?
    /// The modifier keys the person holds, which choose where a row opens.
    private(set) var heldModifiers: EventModifiers = []
    private var completionProposal: AddressCompletion?
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

    private let suggestionDebounce: Duration
    private let fetchSuggestions: @Sendable (URL) async throws -> [String]
    private let isSourceAvailableAction: (BrowserTabRuntimeAssignment) -> Bool
    private let selectTabAction: (BrowserTabRuntimeAssignment, BrowserTabRuntimeAssignment) -> Bool
    private let openURLAction: (BrowserTabRuntimeAssignment, URL, BrowserCommandPaletteOpening) -> Bool
    private let dismissAction: () -> Void
    private let emptySelectionActions: BrowserEmptySelectionPaletteActions?
    /// Where this platform can open a row, which the modifier keys choose among.
    let openings: [BrowserCommandPaletteOpening]

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

    private var isUnscoped: Bool { activeScope == nil }

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
        openings: [BrowserCommandPaletteOpening] = [.here]
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

    /// Tab accepts the completion, enters the named local scope, or moves to
    /// the next row. It never moves focus
    /// out of the field.
    func pressTab() {
        waitForAnswer { [weak self] in
            guard let self else { return }
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

    /// Narrows the palette to `scope`'s kind of result.
    func enter(_ scope: PaletteScope) {
        activeScope = scope
        narrowed()
    }

    /// Leaves the local scope, keeping what was typed.
    @discardableResult
    func leaveScope() -> Bool {
        guard !isUnscoped else { return false }
        activeScope = nil
        requestAnswer()
        replaceText?(query)
        return true
    }

    /// Enters what the text named in the palette's notation, keeping what
    /// followed it as what is typed.
    private func enter(_ entry: PaletteEntry) {
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
    /// history takes its page out of the Space's history. The leading row is never
    /// forgotten this way.
    @discardableResult
    func forgetSelectedRow() -> Bool {
        guard selectedResultIndex > 0, items.indices.contains(selectedResultIndex) else { return false }
        let row = items[selectedResultIndex].row
        guard row.kind.forgetsFromHistory else { return false }
        if row.kind.forgetsFromHistory, let address = row.address, let space {
            browser.removeHistoryAddress(address, in: space.id)
        }
        requestAnswer()
        return true
    }

    func activateSelectedResult() {
        guard items.indices.contains(selectedResultIndex) else { return }
        activate(items[selectedResultIndex].row)
    }

    /// Runs `row` as its kind's activation does. One that closes the palette
    /// closes it; one that narrows to a local scope leaves it open.
    func activate(_ row: PaletteRow) {
        guard shownSequence == sequence else { return }
        let activation = row.kind.activation
        guard BrowserCommandPaletteActivation.of(activation)?.run(row, self) == true, activation.closesPalette else {
            return
        }
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
            settingsPages: commands?.settingsPages ?? [], remote: remote,
            scope: activeScope, allowsCompletion: completionEditing.canPropose(for: text))
    }

    /// The commands the core may rank for `text`. A palette without resting
    /// commands offers none while the text is blank, which the core reads as
    /// nothing typed.
    private func offeredCommands(for text: String) -> [PaletteCommand] {
        guard offersRestingCommands || !text.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }
        return commands?.paletteCommands ?? []
    }

    /// Refreshes visible rows and cancels any request for the previous provider.
    func refreshSearchProvider() { requestAnswer() }

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
                guard await Self.answer(question, from: core)?.suggestionAddress == answer.suggestionAddress,
                    !Task.isCancelled
                else { return }
                let fetched = try await fetchSuggestions(address)
                try Task.checkCancellation()
                guard asked == sequence, !fetched.isEmpty,
                    let merged = await Self.answer(
                        PaletteSuggestions(
                            windowID: question.windowID, text: question.text, commands: question.commands,
                            settingsPages: question.settingsPages, remote: fetched,
                            scope: question.scope, allowsCompletion: question.allowsCompletion),
                        from: core),
                    asked == sequence, merged.suggestionAddress == answer.suggestionAddress
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
