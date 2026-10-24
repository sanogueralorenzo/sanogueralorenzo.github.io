import SwiftUI

/// How the failure page presents its failure: the texts and symbol the core's
/// `NavigationError` declares, with the page's host in a message that names
/// the site.
struct BrowserNavigationFailurePresentation {
    let failure: PageFailure

    var title: LocalizedStringResource { failure.error.title }

    /// The error's message, with the page's host where it spells `%@`.
    var message: Text {
        Text(String(format: String(localized: failure.error.message), failure.displayHost))
    }

    var primarySuggestion: LocalizedStringResource { failure.error.primarySuggestion }

    var secondarySuggestion: LocalizedStringResource { failure.error.secondarySuggestion }

    var symbolName: String { failure.error.symbol }
}
