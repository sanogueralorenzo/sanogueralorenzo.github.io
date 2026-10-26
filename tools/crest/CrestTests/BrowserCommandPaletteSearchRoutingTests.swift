import AppKit
import XCTest

@testable import Crest

/// Native Return routing and suggestion requests respect the selected provider.
@MainActor
final class BrowserCommandPaletteSearchRoutingTests: XCTestCase {

    func testReturnSearchesGoogleAndSuggestionsUseGoogle() async throws {
        var destination: URL?
        let suggestions = SuggestionRecorder()
        let fixture = makeEditor(openURL: { destination = $0 }, fetchSuggestions: { await suggestions.record($0) })
        defer { fixture.window.close() }
        let editor = try XCTUnwrap(fixture.field.currentEditor() as? NSTextView)
        try await type("crest & browser", into: editor, fixture)
        XCTAssertTrue(
            fixture.coordinator.control(
                fixture.field, textView: editor, doCommandBy: #selector(NSResponder.insertNewline(_:))))
        XCTAssertEqual(destination?.absoluteString, "https://www.google.com/search?q=crest%20%26%20browser")
        let asked = await suggestions.hosts
        XCTAssertFalse(asked.isEmpty)
        XCTAssertEqual(Set(asked), ["www.google.com"])
    }

    func testNonGoogleReturnAndSuggestionsNeverFallBackToGoogle() async throws {
        var destination: URL?
        let suggestions = SuggestionRecorder()
        let fixture = makeEditor(
            provider: .duckDuckGo, openURL: { destination = $0 },
            fetchSuggestions: { await suggestions.record($0) })
        defer { fixture.window.close() }
        let editor = try XCTUnwrap(fixture.field.currentEditor() as? NSTextView)
        try await type("crest & browser", into: editor, fixture)
        XCTAssertTrue(
            fixture.coordinator.control(
                fixture.field, textView: editor, doCommandBy: #selector(NSResponder.insertNewline(_:))))
        XCTAssertEqual(destination?.absoluteString, "https://duckduckgo.com/?q=crest%20%26%20browser")
        let asked = await suggestions.hosts
        XCTAssertFalse(asked.isEmpty)
        XCTAssertEqual(Set(asked), ["duckduckgo.com"])
    }

    func testSuggestionRequestsDoNotFollowRedirects() async throws {
        let server = try BrowserPrivacyHTTPServer()
        server.overrideResponse = { request in
            if request.path == "/redirect" {
                return ("302 Found", "Location: /suggestions?q=redirected\r\n", Data())
            }
            return ("200 OK", "Content-Type: application/json\r\n", Data(#"["crest", ["crest browser"]]"#.utf8))
        }
        try await server.start()
        defer { server.stop() }
        let client = BrowserSearchSuggestionClient()
        let direct = try await client.suggestions(from: server.url(host: "localhost", path: "/suggestions?q=crest"))
        XCTAssertEqual(direct, ["crest browser"])
        let redirected = try await client.suggestions(from: server.url(host: "localhost", path: "/redirect?q=crest"))
        XCTAssertTrue(redirected.isEmpty)
        XCTAssertEqual(server.requests.map(\.path), ["/suggestions", "/redirect"])
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
        provider: SearchProvider = .google,
        openURL: @escaping (URL) -> Void = { _ in },
        fetchSuggestions: @escaping @Sendable (URL) async throws -> [String] = { _ in [] }
    ) -> (
        window: NSWindow, field: NSTextField, coordinator: BrowserPlatformCommandPaletteField.Coordinator,
        model: BrowserCommandPaletteModel
    ) {
        let tab = TabState.Seed(title: "Example", url: URL(string: "https://example.com/path"), placement: .current)
        let code = TabState.Seed(title: "Code", url: URL(string: "https://google.com/"), placement: .current)
        let preferences = BrowsingPreferences.seeded
        let space = SpaceState.Seed(
            name: "Test", folders: [], tabs: [tab, code],
            browsingPreferences: preferences)
        var seed = SessionState.Seed(spaces: [space])
        var appPreferences = AppPreferences.default
        appPreferences.searchProvider = provider
        appPreferences.searchSuggestionsEnabled = true
        seed.appPreferences = appPreferences
        let browser = BrowserStore(seed: seed, showing: space.id, tabs: [space.id: tab.id])
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
