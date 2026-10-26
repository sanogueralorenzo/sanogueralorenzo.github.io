import Foundation

/// The native page port used by the existing UI: the engine's view and what it
/// shows. Everything the platform asks of the page's engine goes through its
/// `EnginePage`; portable session commands never receive a platform view.
@MainActor
protocol BrowserPageEngine: AnyObject {
    var registration: BrowserAdapterRegistration { get }
    var nativeView: BrowserEngineView { get }
    /// The engine's own document URL, which can run ahead of the URL the page
    /// last observed; nil before anything loaded.
    var currentURL: URL? { get }
    /// True when the engine reports each navigation's state itself, so the page
    /// takes failures from those reports instead of deriving them from
    /// navigation callbacks.
    var reportsNavigationState: Bool { get }
    /// Brings supplemental history up to date with the engine's own list and
    /// answers the URL of its current entry.
    @discardableResult func synchronizeHistory() -> URL?
    func load(_ request: URLRequest)
    /// One-shot, engine-owned request metadata for a newly created native page.
    /// Tokens never enter the core session, persistence or sync.
    func stageNavigation(_ navigation: BrowserEngineNavigation, expecting url: URL) -> Bool
    /// Content bridges run by the engine itself, or nil when the page installs
    /// them through the engine's own API.
    var contentScripting: (any BrowserPageContentScripting)? { get }
    /// The engine's measure of the sound the page plays, band by band, or nil
    /// when the engine does not measure it.
    var audioSpectrum: BrowserAudioSpectrumFeed? { get }
}

extension BrowserPageEngine {
    var reportsNavigationState: Bool { false }
    @discardableResult func synchronizeHistory() -> URL? { nil }
    func stageNavigation(_ navigation: BrowserEngineNavigation, expecting url: URL) -> Bool { false }
    var contentScripting: (any BrowserPageContentScripting)? { nil }
    var audioSpectrum: BrowserAudioSpectrumFeed? { nil }
}

/// A link an engine staged for a new page's first load, which keeps the
/// referrer and initiator it had where it was followed.
struct BrowserEngineNavigation: Equatable, Sendable {
    let implementation: BrowserEngineImplementation
    /// The engine's identity for the link it staged.
    let linkID: UUID
    /// The core's page the link was followed in, for an engine whose staged
    /// links go through the core; nil for one that keeps them itself.
    var sourcePageID: UUID?
}
