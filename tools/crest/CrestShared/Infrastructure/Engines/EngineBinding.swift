import Foundation

/// A browsing engine the core hosts pages on. It builds the engine's page when
/// the core asks, closes it when asked, and reports what happens to its pages
/// through the `Engines` it is attached to. Chromium and WebKit each have one.
@MainActor
protocol EngineBinding: AnyObject {
    /// What the engine offers. Its registration with the core carries the
    /// capabilities it supports.
    var integration: BrowserAdapterRegistration { get }

    /// Called once, when the binding registers: the registry it finds page
    /// requests in and reports through.
    func attach(to engines: Engines)

    /// Runs one command the core issued, never on the stack of another.
    func run(_ command: EngineCommand)
}
