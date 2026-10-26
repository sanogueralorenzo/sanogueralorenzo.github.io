import CrestCoreABI
import Foundation

/// A browsing engine whose binding is written outside Swift, as Chromium's is
/// in C++. The core runs the binding's commands through the binding's own
/// function table, and the binding reports what its pages do straight to the
/// core, so neither passes through Swift. The platform only hosts each page
/// the engine creates.
@MainActor
protocol NativeEngineBinding: AnyObject {
    /// What the engine offers. Its registration with the core carries the
    /// capabilities it supports.
    var integration: BrowserAdapterRegistration { get }

    /// The binding's function table, which the core copies when it registers.
    var table: crest_engine_binding_t { get }

    /// The engine contract the binding was built against. The core refuses a
    /// binding built against any other, such as a stale prebuilt engine.
    var fingerprint: [UInt8] { get }

    /// What the platform hosts for `page`, which the engine creates on its own
    /// once the core asks it to.
    func host(_ page: CorePage) -> any EngineHostedPage

    /// The icon the engine found for the document `pageID` shows, which the
    /// binding keeps until a tab adopts it.
    func icon(of pageID: UUID) -> Data?
}
