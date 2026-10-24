import Foundation

/// The engine integrations each composition can select. `current` comes from
/// the composition (`BrowserEngineRegistration+Composition.swift` for WebKit,
/// the Chromium framework's own extension otherwise).
enum BrowserEngineRegistration {

    // MARK: - Variables

    #if os(macOS)
        private static let webKitImplementation = BrowserEngineImplementation.webKitMacOS
    #else
        private static let webKitImplementation = BrowserEngineImplementation.webKitIOS
    #endif

    /// Native WebKit page and profile ports. Protected media plays through the
    /// platform's FairPlay. A staged Peek navigation replays
    /// only a GET link's URL and referrer: WebKit has no public way to carry the
    /// initiating frame's origin, user activation or sandbox into another page.
    /// Find reports whether a match exists but not how many, because WebKit's
    /// public find API has no match count. On the Mac, before-unload uses
    /// WebKit's desktop close and prompt SPI; a WebKit without it closes pages
    /// without asking.
    static let webKit = BrowserAdapterRegistration(
        kind: .webKit,
        implementation: webKitImplementation,
        supported: [
            .pages, .navigation, .find, .zoom, .interactionState, .pageResidency,
            .popups, .workspaceProfiles, .workspaceTransfer, .profileDeletion,
            .contentBlocking, .downloads, .permissions, .reader, .translation,
            .selectionTranslation, .localFiles, .protectedMedia,
        ] + desktopWebKit,
        unavailable: [.extensions],
        archiveFormat: .webArchive)

    /// The native macOS Chromium host with Crest's page and profile ports.
    ///
    /// - A certificate error shows Chromium's own warning page, and proceeding
    ///   past it happens there: the decision is the engine profile's, not a
    ///   Crest certificate override.
    /// - Extensions cover actions, installation, side panels and per-Space
    ///   permissions; full API parity and Apple password-helper pairing remain
    ///   incomplete.
    /// - Whole-page translation rewrites the main document through the
    ///   engine's content scripting, as WebKit's does through its own.
    /// - Protected media is unavailable: the engine carries no Widevine, and a
    ///   page that asks for it moves to WebKit.
    /// - Site permission decisions reach the engine as content settings for the
    ///   page's current site; the host has no command to stop live camera,
    ///   microphone or location use directly, so revocation relies on the engine
    ///   ending it when the setting blocks.
    /// - A page's web notifications reach Crest's own system delivery, which
    ///   the WebKit pages share; a service worker's or an extension's
    ///   notifications are closed without showing.
    static let chromium = BrowserAdapterRegistration(
        kind: .chromium,
        implementation: .chromiumMacOS,
        supported: [
            .pages, .navigation, .find, .zoom, .interactionState, .pageResidency,
            .workspaceProfiles, .workspaceTransfer, .profileDeletion,
            .beforeUnload, .downloads, .permissions, .viewportCapture, .inspector, .internalPages,
            .fullPageCapture, .pdf, .webArchive, .print, .localFiles,
            .extensions, .translation, .selectionTranslation, .popups, .featureFlags, .audioSpectrum,
        ],
        unavailable: [.reader, .contentBlocking, .protectedMedia],
        archiveFormat: .mhtml)

    private static var desktopWebKit: [EngineCapability] {
        #if os(macOS)
            [.viewportCapture, .fullPageCapture, .pdf, .webArchive, .print, .inspector, .featureFlags, .beforeUnload]
        #else
            []
        #endif
    }
}
