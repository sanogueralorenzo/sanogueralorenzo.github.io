import AppKit

@MainActor
private final class Workflow {
    let fixture: PiFixture
    let service: PiService
    let menu = AppMenu()
    let pasteboard = NSPasteboard.withUniqueName()
    let defaultsName = "rewrite-workflow-test-" + UUID().uuidString
    var source = "Might finish Friday, 12 June."
    lazy var controller = RewriteController(processor: service, menuBar: menu,
        defaults: UserDefaults(suiteName: defaultsName)!, pasteboard: pasteboard, captureText: { [unowned self] in source })

    init() throws {
        fixture = try PiFixture(); service = PiService(executable: fixture.executable)
        pasteboard.setString("Previous clipboard", forType: .string)
        menu.onRewrite = { [unowned self] in controller.begin() }
        menu.onProvider = { [unowned self] in controller.selectProvider($0) }
    }
    func close() {
        controller.cancel(); service.shutdown(); menu.remove(); pasteboard.releaseGlobally()
        UserDefaults.standard.removePersistentDomain(forName: defaultsName)
    }
    var dotHidden: Bool {
        let dots = menu.item.button!.subviews.filter { String(describing: type(of: $0)) == "StatusDot" }
        return dots.count == 1 && dots[0].isHidden
    }
    func beginFromMenu() {
        let native = menu.item.menu!
        native.performActionForItem(at: native.items.firstIndex { $0.title == "Rewrite" }!)
    }
    func finished() async throws {
        try await eventually("Rewrite did not finish") { !controller.isRewriting }
    }
}

@MainActor
enum WorkflowTests {
    static func completion() async throws {
        let run = try Workflow(); defer { run.close() }
        run.beginFromMenu()
        try expect(run.controller.isRewriting && !run.dotHidden, "Menu did not start the rewrite and show progress")
        try await run.finished()
        try expect(run.pasteboard.string(forType: .string) == "Edited: " + run.source, "Completed rewrite was not copied")
        try expect(run.dotHidden, "Completion did not clear the dot")
        let titles = run.menu.item.menu!.items.filter { !$0.isHidden && !$0.isSeparatorItem }.map(\.title)
        try expect(titles == ["Rewrite", "Provider", "Quit"], "Completion did not return to the idle menu")
    }
    static func restart() async throws {
        let run = try Workflow(); defer { run.close() }
        try run.fixture.mode("hold")
        run.controller.begin()
        try await eventually("First rewrite never reached Pi") { run.fixture.count("prompt") == 1 }
        run.controller.begin() // A second Option-R cancels.
        try expect(!run.controller.isRewriting && run.dotHidden, "Cancellation did not clear progress")
        try expect(run.pasteboard.string(forType: .string) == "Previous clipboard", "Cancelled rewrite changed the clipboard")
        try run.fixture.mode("normal"); run.source = "Newest text"
        run.controller.begin() // No waiting for the old task to unwind.
        try await run.finished()
        try expect(run.pasteboard.string(forType: .string) == "Edited: Newest text", "Immediate restart lost or copied stale output")
        try expect(run.fixture.count("prompt") == 2 && run.dotHidden, "Restart retried or left progress visible")
    }
    static func providerSwitch() async throws {
        let run = try Workflow(); defer { run.close() }
        try run.fixture.mode("hold-auth")
        run.controller.begin()
        try await eventually("Preparation never reached auth") { run.fixture.count("auth") == 1 }
        try run.fixture.mode("normal")
        let providers = run.menu.item.menu!.items.first { $0.title == "Provider" }!.submenu!
        providers.performActionForItem(at: 1)
        try expect(run.controller.provider == .anthropic && providers.items[1].state == .on, "Provider menu did not switch")
        run.source = "Use the new provider"; run.controller.begin()
        try await run.finished()
        try expect(run.pasteboard.string(forType: .string) == "Edited: Use the new provider", "Rewrite failed after switching during preparation")
        let starts = run.fixture.events.filter { $0["event"] as? String == "started" }
        try expect(starts.count == 1 && starts[0]["provider"] as? String == "anthropic", "Old provider survived preparation cancellation")
        try expect(run.fixture.count("prompt") == 1 && run.dotHidden, "Switch sent stale text or left progress visible")
    }
    static func invalidOutput() async throws {
        let run = try Workflow(); defer { run.close() }
        try run.fixture.mode("empty")
        run.controller.begin(); try await run.finished()
        try expect(run.pasteboard.string(forType: .string) == "Previous clipboard", "Invalid output destroyed the clipboard")
        try expect(!run.dotHidden && run.menu.item.button!.toolTip!.contains("no text"), "Invalid output did not report the validation error")
    }
}
