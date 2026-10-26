#if CREST_CHROMIUM_HOST
    import AppKit

    /// Crest's own UI, as Chromium's Mac shell asks for it: its windows, the
    /// application's quit, reopen and external opens, system sign-in, and what
    /// the engine's browser window asks of Crest's. Crest's shared Mac shell
    /// answers each one; the composition answers what only Chromium asks.
    @MainActor
    final class ChromiumMacUI: NSObject, CrestMacUI {
        // MARK: - Types

        private final class Placement: NSObject, CrestEngineWindowPlacement {
            let window: UUID
            let space: UUID

            init(window: UUID, space: UUID) {
                self.window = window
                self.space = space
            }
        }

        // MARK: - Variables

        private var shell: BrowserMacShell? { ChromiumComposition.shell }

        // MARK: - Actions - Windows

        func window(id: UUID?) -> NSWindow? {
            shell?.window(for: id)
        }

        func restoredFrame(for window: NSWindow) -> NSRect {
            (window as? BrowserMacWindow)?.restoredFrame ?? window.frame
        }

        func wasZoomedBeforeFullScreen(_ window: NSWindow) -> Bool {
            (window as? BrowserMacWindow)?.wasZoomedBeforeFullScreen ?? false
        }

        func reserveEngineWindow(profile: UUID, ownWindow: Bool) -> (any CrestEngineWindowPlacement)? {
            shell?.reserveEngineWindow(forProfile: profile, ownWindow: ownWindow).map {
                Placement(window: $0.window, space: $0.space)
            }
        }

        func presentEngineWindow(_ windowID: UUID, space spaceID: UUID, focused: Bool) {
            shell?.presentEngineWindow(windowID, space: spaceID, focused: focused)
        }

        // MARK: - Actions - Application

        func deferQuit() -> Bool { ChromiumComposition.deferQuit() }

        func reopen() -> Bool { shell?.reopen() ?? false }

        func openExternal(_ urls: [URL]) -> Bool { shell?.openExternal(urls) ?? false }

        func dockMenu() -> NSMenu? { shell?.dockMenu() }

        func openAuthenticationSession(_ url: URL, window windowID: UUID) -> Bool {
            guard let host = ChromiumComposition.engineHost else { return false }
            return shell?.openAuthenticationSession(url, window: windowID) {
                host.cancelAuthenticationSession(window: windowID)
            } ?? false
        }

        func closeAuthenticationSession(window windowID: UUID) {
            shell?.closeAuthenticationSession(windowID)
        }

        // MARK: - Actions - The engine's browser window

        /// A key the engine is about to hand a page, which sees it first unless
        /// the core reserves its command from pages. The engine hands a key the
        /// page lets go to the menu bar.
        func handleShortcut(_ event: NSEvent) -> Bool { shell?.handleShortcut(event, pageSeesFirst: true) ?? false }

        func focusLocation() { shell?.focusLocation() }

        func bookmarkActivePage() { shell?.bookmarkActivePage() }

        func translatePage() { ChromiumComposition.translatePage() }

        func translate(_ text: String) { ChromiumComposition.translateText(text) }

        func showTabSearch() { shell?.showTabSearch() }

        func showUnavailable(_ feature: UnavailableEngineFeature) {
            let notice = ChromiumUnavailableFeatureNotice.notice(for: feature)
            ChromiumComposition.showNativeNotice(String(localized: notice.message), icon: notice.symbol)
        }

        func showEngineNotice(_ message: String, kind: EngineNoticeKind) {
            ChromiumComposition.showNativeNotice(message, icon: kind == .linkCopied ? "link" : "checkmark.circle")
        }

        // MARK: - Actions - Pages

        func addPageMenuItems(to menu: NSMenu, page pageID: UUID, link: URL?, selection: String?) {
            ChromiumComposition.chromiumEngine?.page(pageID)?.addMenuItems(to: menu, link: link, selection: selection)
        }

        func beginLinkDrag(_ url: URL, title: String, page pageID: UUID) -> Bool {
            ChromiumComposition.chromiumEngine?.page(pageID)?.beginLinkDrag(url, title: title) == true
        }
    }

    /// What Crest says, and the symbol it shows, for a Chromium feature whose
    /// own UI this build never shows.
    private struct ChromiumUnavailableFeatureNotice: Sendable {
        // MARK: - Static Variables

        static let autofill = ChromiumUnavailableFeatureNotice(
            feature: .autofill, message: "Autofill is not connected in Crest yet.", symbol: "person")
        static let addressAutofill = ChromiumUnavailableFeatureNotice(
            feature: .addressAutofill, message: "Address autofill is not available in Crest yet.",
            symbol: "person.text.rectangle")
        static let addressAutofillSignIn = ChromiumUnavailableFeatureNotice(
            feature: .addressAutofillSignIn, message: "Address autofill sign-in is not available in Crest yet.",
            symbol: "person.crop.circle.badge.plus")
        static let autofillAI = ChromiumUnavailableFeatureNotice(
            feature: .autofillAI, message: "Autofill with AI is not available in Crest yet.", symbol: "sparkles")
        static let autofillOffers = ChromiumUnavailableFeatureNotice(
            feature: .autofillOffers, message: "Autofill offers are not available in Crest yet.", symbol: "tag")
        static let autofillReauthentication = ChromiumUnavailableFeatureNotice(
            feature: .autofillReauthentication, message: "Autofill reauthentication is not available in Crest yet.",
            symbol: "lock.shield")
        static let paymentAutofill = ChromiumUnavailableFeatureNotice(
            feature: .paymentAutofill, message: "Payment autofill is not available in Crest yet.",
            symbol: "creditcard")
        static let virtualCardEnrollment = ChromiumUnavailableFeatureNotice(
            feature: .virtualCardEnrollment, message: "Virtual card enrollment is not available in Crest yet.",
            symbol: "creditcard.trianglebadge.exclamationmark")
        static let profiles = ChromiumUnavailableFeatureNotice(
            feature: .profiles, message: "Profiles are not available in Crest yet.", symbol: "person.crop.circle")
        static let eyeDropper = ChromiumUnavailableFeatureNotice(
            feature: .eyeDropper, message: "The eye dropper is not available in Crest yet.", symbol: "eyedropper")
        static let caretBrowsing = ChromiumUnavailableFeatureNotice(
            feature: .caretBrowsing, message: "Caret browsing is not available in Crest yet.", symbol: "text.cursor")
        static let privateBrowsing = ChromiumUnavailableFeatureNotice(
            feature: .privateBrowsing, message: "This private browsing option is not available in Crest yet.",
            symbol: "eye.slash")
        static let chromeLabs = ChromiumUnavailableFeatureNotice(
            feature: .chromeLabs, message: "Chrome Labs is not available in Crest.", symbol: "flask")

        /// Every feature the host header names, each with its notice.
        static let all: [ChromiumUnavailableFeatureNotice] = [
            autofill, addressAutofill, addressAutofillSignIn, autofillAI, autofillOffers, autofillReauthentication,
            paymentAutofill, virtualCardEnrollment, profiles, eyeDropper, caretBrowsing, privateBrowsing, chromeLabs,
        ]

        /// The notice for a feature a newer host names before Crest has words
        /// for it.
        static let fallback = ChromiumUnavailableFeatureNotice(
            feature: nil, message: "This is not available in Crest yet.", symbol: "info.circle")

        // MARK: - Variables

        let feature: UnavailableEngineFeature?
        let message: LocalizedStringResource
        let symbol: String

        // MARK: - Actions - Lookup

        static func notice(for feature: UnavailableEngineFeature) -> ChromiumUnavailableFeatureNotice {
            all.first { $0.feature == feature } ?? fallback
        }
    }
#endif
