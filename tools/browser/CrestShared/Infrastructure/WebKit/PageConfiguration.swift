import Foundation
import WebKit

/// Crest's platform default for typographic quote replacement in webpage editors.
///
/// WebKit on macOS reads this exact app-domain key before consulting the system
/// Smart Quotes preference. Desktop webpage editors are more likely to expect
/// literal punctuation, while iOS keeps the system's touch-keyboard behavior.
enum BrowserAutomaticQuoteSubstitutionPreference {
    static let key = "WebAutomaticQuoteSubstitutionEnabled"

    #if os(macOS)
        static let defaultIsEnabled = false
    #else
        static let defaultIsEnabled = true
    #endif

    static func registerDefault(defaults: UserDefaults = .standard) {
        defaults.register(defaults: [key: defaultIsEnabled])
    }
}

@MainActor
enum BrowserPageConfiguration {
    /// Builds the configuration every Crest page shares.
    ///
    /// `preferredContentMode` and `decorate` are the two seams a platform shell
    /// needs: macOS asks sites for their desktop presentation while mobile takes
    /// the recommended one, and `decorate` runs last so a platform can add its own
    /// media policy, content scripts, and bridges — or override a shared default —
    /// without hand-rolling a second configuration that drifts from this one.
    static func make(
        for profile: BrowsingProfile,
        websiteDataStore: WKWebsiteDataStore? = nil,
        contentRuleList: WKContentRuleList? = nil,
        contentRuleLists: [WKContentRuleList] = [],
        preferredContentMode: WKWebpagePreferences.ContentMode = .desktop,
        decorate: @MainActor (WKWebViewConfiguration) -> Void = { _ in }
    ) -> WKWebViewConfiguration {
        let webpagePreferences = WKWebpagePreferences()
        webpagePreferences.preferredContentMode = preferredContentMode
        webpagePreferences.allowsContentJavaScript = true

        let preferences = WKPreferences()
        preferences.isElementFullscreenEnabled = true
        // WebKit can distinguish a user-activated `window.open()` from an
        // unsolicited automatic window. Keep automatic windows blocked by
        // default; each page enables them only for an explicitly allowed site.
        // User-activated new tabs and windows are unaffected by this setting.
        preferences.javaScriptCanOpenWindowsAutomatically = false
        // Resident background tabs stay alive for instant host swaps. macOS may
        // replace this default with the user's background-activity preference.
        preferences.inactiveSchedulingPolicy = .suspend
        #if os(macOS)
            BrowserWebKitFeatureFlagStore.active.apply(to: preferences)
        #endif

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore =
            websiteDataStore
            ?? BrowserWebsiteDataStore.launchScoped(for: profile)
        configuration.defaultWebpagePreferences = webpagePreferences
        configuration.preferences = preferences
        configuration.applicationNameForUserAgent = safariCompatibleApplicationName
        configuration.upgradeKnownHostsToHTTPS = true
        configuration.allowsAirPlayForMediaPlayback = true
        configuration.suppressesIncrementalRendering = false
        configuration.limitsNavigationsToAppBoundDomains = false
        for ruleList in contentRuleLists {
            configuration.userContentController.add(ruleList)
        }
        if let contentRuleList,
            !contentRuleLists.contains(where: { $0 === contentRuleList })
        {
            configuration.userContentController.add(contentRuleList)
        }
        decorate(configuration)
        return configuration
    }

    static var safariCompatibleApplicationName: String? {
        // WKWebView omits Safari's browser tokens. Supply the platform's native
        // compatibility suffix without an app token so sign-in providers evaluate
        // Crest as the user-driven browser it is instead of an embedded app flow.
        return BrowserPlatformUserAgent.applicationName
    }
}
