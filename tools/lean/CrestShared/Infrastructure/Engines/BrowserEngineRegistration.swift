import Foundation

/// The capabilities provided by the native WebKit browser.
enum BrowserEngineRegistration {

    // MARK: - Variables

    static var current: BrowserAdapterRegistration { webKit }

    #if os(macOS)
        private static let webKitImplementation = BrowserEngineImplementation.webKitMacOS
    #else
        private static let webKitImplementation = BrowserEngineImplementation.webKitIOS
    #endif

    /// Native WebKit page and profile ports. Protected media plays through the
    /// platform's FairPlay. A staged page navigation replays
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

    private static var desktopWebKit: [EngineCapability] {
        #if os(macOS)
            [.viewportCapture, .fullPageCapture, .pdf, .webArchive, .print, .inspector, .featureFlags, .beforeUnload]
        #else
            []
        #endif
    }
}
