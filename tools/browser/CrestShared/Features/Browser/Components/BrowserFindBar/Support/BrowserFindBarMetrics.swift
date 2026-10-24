import CoreGraphics

/// How a shell spells the search result beside the query.
enum BrowserFindMatchStatusStyle: Equatable, Sendable {
    /// The state in words, in a column wide enough for the longest of them.
    case label

    /// A symbol, and a spinner while WebKit is still looking.
    case symbol
}

/// The drawn geometry of the find bar, resolved once per shell rather than
/// spelled out by each fork of the bar.
///
/// The bar holds the same four things everywhere — the query field, the result,
/// the two match chevrons, and close — and what changes between shells is only
/// how big they are, how far apart they sit, and how the result is spelled.
struct BrowserFindBarMetrics: Equatable, Sendable {
    /// The gap between adjacent items.
    let itemSpacing: CGFloat

    let leadingPadding: CGFloat

    let trailingPadding: CGFloat

    /// The width the query field is pinned to, or `nil` where the field takes
    /// whatever room the bar is given.
    ///
    /// A pointer shell floats the bar over a corner of the page and has to
    /// decide its own width; a touch shell hands it a bar that already spans
    /// the chrome.
    let queryWidth: CGFloat?

    /// The band the bar occupies, read together with `growsWithContent`.
    let barHeight: CGFloat

    /// Whether `barHeight` is a floor the bar may grow past.
    ///
    /// A pointer shell pins the panel to one exact height. A touch shell lets
    /// an accessibility text size push the bar taller rather than clip it.
    let growsWithContent: Bool

    /// The frame each chevron and the close control claim, or `nil` where a
    /// control keeps the size its style gives it.
    ///
    /// Touch decides this like it decides the sidebar's trailing control: the
    /// three controls sit shoulder to shoulder, and each has to be hittable by
    /// the least precise input the shell accepts.
    let controlSize: CGSize?

    /// How the search result is spelled beside the query.
    let matchStatusStyle: BrowserFindMatchStatusStyle

    /// The column the result is drawn in — a minimum for a word, an exact
    /// width for a symbol.
    let matchStatusWidth: CGFloat

    /// A pointer shell: a fixed-width panel floating over the page, compact
    /// controls, and the result spelled out.
    static let pointer = BrowserFindBarMetrics(
        itemSpacing: 6,
        leadingPadding: 10,
        trailingPadding: 10,
        queryWidth: 190,
        barHeight: 36,
        growsWithContent: false,
        controlSize: nil,
        matchStatusStyle: .label,
        matchStatusWidth: 62
    )

    /// A touch shell: a bar that spans the chrome it is placed in, full 44pt
    /// targets, and a symbol where the pointer shell has room for a word.
    ///
    /// The targets are literals rather than `CrestLayout.minimumHitTarget`, for
    /// the same reason the touch sidebar profiles' are: this profile is
    /// compared against from a suite hosted on macOS, where that token resolves
    /// to the pointer shell's 28, and a touch control still has to be 44.
    static let touch = BrowserFindBarMetrics(
        itemSpacing: 6,
        leadingPadding: 14,
        trailingPadding: 4,
        queryWidth: nil,
        barHeight: 44,
        growsWithContent: true,
        controlSize: CGSize(width: 40, height: 44),
        matchStatusStyle: .symbol,
        matchStatusWidth: 24
    )

    /// The profile a shell draws its find bar with.
    ///
    /// Touch decides it for the same reason it decides the sidebar's rows: the
    /// bar is a row of hit targets before it is a panel, so its sizing follows
    /// the least precise input the shell accepts.
    static func resolve(
        _ capabilities: BrowserInteractionCapabilities
    ) -> BrowserFindBarMetrics {
        capabilities.supportsTouch ? .touch : .pointer
    }

    /// The lift under the bar. Both shells draw it identically, and neither
    /// draws it once the reader has asked for reduced transparency.
    static let shadowOpacity = 0.14
    static let shadowRadius: CGFloat = 12
    static let shadowOffset: CGFloat = 5
}
