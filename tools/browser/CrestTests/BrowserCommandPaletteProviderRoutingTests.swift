import AppKit
import XCTest

@testable import Crest

/// The native field routes Tab, Return and Escape as the palette's keyboard
/// model says: Tab enters only the provider the core offers for exactly what
/// was typed, before a completion when the text is its shortcut, never while
/// text is being composed or the caret is not at the end; a provider sends
/// what was typed and asks suggestions only of itself; Escape leaves it with
/// the text kept.
@MainActor
final class BrowserCommandPaletteProviderRoutingTests: XCTestCase {
    func testTabEntersTheOfferedProviderWhichAloneReceivesTheQuery() async throws {
        var destination: URL?
        let suggestions = SuggestionRecorder()
        let fixture = makeEditor(openURL: { destination = $0 }, fetchSuggestions: { await suggestions.record($0) })
        defer { fixture.window.close() }
        let editor = try XCTUnwrap(fixture.field.currentEditor() as? NSTextView)

        try await type("yt", into: editor, fixture)
        XCTAssertEqual(fixture.model.providerOffer?.title, "YouTube")
        XCTAssertTrue(
            fixture.coordinator.control(
                fixture.field, textView: editor, doCommandBy: #selector(NSResponder.insertTab(_:))))
        XCTAssertEqual(fixture.model.activeProvider?.title, "YouTube")
        XCTAssertEqual(editor.string, "")

        await suggestions.reset()
        try await type("crest & browser", into: editor, fixture)
        XCTAssertTrue(
            fixture.coordinator.control(
                fixture.field, textView: editor, doCommandBy: #selector(NSResponder.insertNewline(_:))))
        XCTAssertEqual(
            destination?.absoluteString, "https://www.youtube.com/results?search_query=crest%20%26%20browser")
        let asked = await suggestions.hosts
        XCTAssertFalse(asked.isEmpty)
        XCTAssertEqual(Set(asked), ["suggestqueries.google.com"], "A provider asks suggestions only of itself.")

        XCTAssertTrue(
            fixture.coordinator.control(
                fixture.field, textView: editor, doCommandBy: #selector(NSResponder.cancelOperation(_:))))
        XCTAssertNil(fixture.model.activeProvider)
        XCTAssertEqual(editor.string, "crest & browser")
    }

    func testTabOnAnExactShortcutEntersItsProviderWhileAnAddressCompletes() async throws {
        let fixture = makeEditor()
        defer { fixture.window.close() }
        let editor = try XCTUnwrap(fixture.field.currentEditor() as? NSTextView)

        try await type("github", into: editor, fixture)
        XCTAssertEqual(fixture.model.urlCompletion?.accepted, "github.com")
        XCTAssertEqual(fixture.model.providerOffer?.title, "GitHub")
        XCTAssertTrue(
            fixture.coordinator.control(
                fixture.field, textView: editor, doCommandBy: #selector(NSResponder.insertTab(_:))))
        XCTAssertEqual(fixture.model.activeProvider?.title, "GitHub")
    }

    func testCompositionAndACaretAwayFromTheEndNeverEnterAProvider() async throws {
        let fixture = makeEditor()
        defer { fixture.window.close() }
        let editor = try XCTUnwrap(fixture.field.currentEditor() as? NSTextView)

        try await type("yt", into: editor, fixture)
        editor.setSelectedRange(NSRange(location: 1, length: 0))
        fixture.coordinator.editingChanged()
        XCTAssertNil(fixture.model.providerOffer)
        _ = fixture.coordinator.control(
            fixture.field, textView: editor, doCommandBy: #selector(NSResponder.insertTab(_:)))
        XCTAssertNil(fixture.model.activeProvider)

        editor.setSelectedRange(NSRange(location: 2, length: 0))
        editor.setMarkedText(
            "t", selectedRange: NSRange(location: 1, length: 0), replacementRange: NSRange(location: 2, length: 0))
        fixture.coordinator.editingChanged()
        XCTAssertFalse(
            fixture.coordinator.control(
                fixture.field, textView: editor, doCommandBy: #selector(NSResponder.insertTab(_:))),
            "Tab belongs to the input method while text is being composed.")
        XCTAssertNil(fixture.model.activeProvider)
    }

    private func type(
        _ text: String, into editor: NSTextView,
        _ fixture: (
            window: NSWindow, field: NSTextField, coordinator: BrowserPlatformCommandPaletteField.Coordinator,
            model: BrowserCommandPaletteModel
        )
    ) async throws {
        editor.insertText(text, replacementRange: editor.selectedRange())
        fixture.coordinator.editingChanged()
        await fixture.model.waitForPendingResults()
    }

    private func makeEditor(
        openURL: @escaping (URL) -> Void = { _ in },
        fetchSuggestions: @escaping @Sendable (URL) async throws -> [String] = { _ in [] }
    ) -> (
        window: NSWindow, field: NSTextField, coordinator: BrowserPlatformCommandPaletteField.Coordinator,
        model: BrowserCommandPaletteModel
    ) {
        let tab = TabState.Seed(title: "Example", url: URL(string: "https://example.com/path"), placement: .current)
        let code = TabState.Seed(title: "Code", url: URL(string: "https://github.com/"), placement: .current)
        var preferences = BrowsingPreferences.seeded
        preferences.followsDefaultSuggestions = false
        preferences.searchSuggestionsEnabled = true
        let space = SpaceState.Seed(
            name: "Test", symbol: "globe", accent: .indigo, folders: [], tabs: [tab, code],
            browsingPreferences: preferences)
        let browser = BrowserStore(
            seed: SessionState.Seed(spaces: [space]), showing: space.id, tabs: [space.id: tab.id])
        BrowserSearchCatalog.restore(into: browser.core, locale: Locale(identifier: "en_US"))
        let model = BrowserCommandPaletteModel(
            browser: browser, space: browser.spaceModel(space.id), selectedTabID: tab.id, initialQuery: "",
            commands: nil,
            suggestionDebounce: .zero, fetchSuggestions: fetchSuggestions, isSourceAvailable: { _ in true },
            selectTab: { _, _ in false },
            openURL: { _, url, _ in
                openURL(url)
                return true
            }, dismiss: {})
        let view = BrowserPlatformCommandPaletteField(
            model: model, presentation: .overlay, identifier: "test-field", focused: false)
        let coordinator = view.makeCoordinator()
        let field = view.makeField(coordinator: coordinator)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 80), styleMask: .borderless, backing: .buffered,
            defer: false)
        window.isReleasedWhenClosed = false
        field.frame = NSRect(x: 10, y: 20, width: 450, height: 32)
        window.contentView?.addSubview(field)
        window.makeFirstResponder(field)
        field.selectText(nil)
        return (window, field, coordinator, model)
    }

    private actor SuggestionRecorder {
        private(set) var hosts: [String] = []

        func record(_ url: URL) -> [String] {
            hosts.append(url.host() ?? "")
            return []
        }

        func reset() {
            hosts = []
        }
    }
}
