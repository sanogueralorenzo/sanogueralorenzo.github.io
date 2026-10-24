import Foundation

/// One engine's direct path from the platform to its pages: view work such as
/// going back, reloading or finding text, which the engine answers at once,
/// and the presentations it sends when work finishes later. Every engine
/// answers the same requests; the core never sees them.
@MainActor
protocol EnginePages: AnyObject {
    /// Whether synchronous queries can reach the engine. A deferred runtime
    /// accepts view actions while starting, but has no document to query yet.
    var isReady: Bool { get }

    /// Asks the engine for `request` and answers what it answered.
    @discardableResult
    func request<Request: PageRequest>(_ request: Request) -> Request.Answer

    /// Sends `page` the presentations about it, while it lives.
    func attach(_ page: EnginePage)
}

extension EnginePages {
    var isReady: Bool { true }
}

/// The pages attached to one engine's direct path, held weakly so each goes
/// with its owner.
@MainActor
struct AttachedEnginePages {
    // MARK: - Types

    private struct WeakPage {
        weak var page: EnginePage?
    }

    // MARK: - Variables

    private var pages: [UUID: WeakPage] = [:]

    // MARK: - Actions - Pages

    mutating func attach(_ page: EnginePage) {
        pages = pages.filter { $0.value.page != nil }
        pages[page.id] = WeakPage(page: page)
    }

    /// Hands a presentation to the page it is about, if that page is attached.
    func present(_ presentation: EnginePresentation) {
        guard let pageID = presentation.pageID else { return }
        pages[pageID]?.page?.receive(presentation)
    }
}
