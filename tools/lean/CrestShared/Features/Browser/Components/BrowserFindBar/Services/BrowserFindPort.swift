/// Everything the find bar needs from the page layer, and nothing else.
///
/// The two shells reach different pages — one a pooled windowed page, the other
/// the compact shell's single resident page — but the bar only ever asks the
/// same few questions, and both pages already answer them with identical
/// signatures. They live here as closures rather than behind a protocol, for
/// the same reason `BrowserSidebarNavigationPort`'s do: there is no third
/// implementation to swap in, only two concrete pages, each bound where its
/// shell presents the bar.
///
/// `query`, `matchState`, and `focusRequest` read through their page at call time rather
/// than carrying a snapshot, so Observation still tracks them — the result the
/// bar draws has to change when WebKit answers, and the field has to be asked
/// for again when the page is.
///
/// None of the closures carries an isolation annotation, exactly like
/// `BrowserSidebarNavigationPort`: annotating them `@MainActor` would also make
/// them `@Sendable`, which the plain function values a View hands over are not.
/// The struct itself is isolated instead.
@MainActor
struct BrowserFindPort {
    /// Searches the page and moves to the match the direction asks for. An
    /// empty query clears the search rather than running it.
    let find: (String, BrowserFindDirection) -> Void

    /// The query retained by this page while its tab is temporarily hidden.
    let query: () -> String

    /// What the page can say about the search right now.
    let matchState: () -> BrowserFindMatchState

    /// Which match is selected, out of how many, when the page's engine counts.
    var matches: () -> BrowserFindMatches? = { nil }

    /// How many times the page has been asked for find. Every ask is a request
    /// for the query field, including the ones made while the bar is already
    /// on screen.
    let focusRequest: () -> Int

    /// Whether the bar takes the query field when it appears. A bar brought
    /// back by finding again leaves the keys with the page.
    var focusesQueryField: () -> Bool = { true }

    /// Closes the bar and clears the page's highlight.
    let dismiss: () -> Void
}
