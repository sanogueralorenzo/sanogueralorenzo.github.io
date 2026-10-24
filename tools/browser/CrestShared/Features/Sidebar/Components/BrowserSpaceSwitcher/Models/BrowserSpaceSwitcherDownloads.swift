import SwiftUI

/// What the switcher's common-lists badge is drawn from.
///
/// The badge counts the finished downloads nobody has looked at yet and turns
/// red as soon as any download in the profile needs attention, so it needs the
/// whole list and not only the unseen part of it. Both are read through the
/// download center at body time, which is what keeps the badge live as
/// downloads land.
struct BrowserSpaceSwitcherDownloads {
    /// Everything the selected Space's profile has downloaded.
    let items: [DownloadState]

    /// The finished downloads that have not been acknowledged.
    let newItems: [DownloadState]

    /// The Space's own accent, which the badge wears unless something in the
    /// list needs attention.
    let badgeColor: Color

    static let none = BrowserSpaceSwitcherDownloads(
        items: [],
        newItems: [],
        badgeColor: .accentColor
    )
}
