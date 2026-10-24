import CoreGraphics

/// The drawn geometry of a stacked split-group row, resolved once per shell
/// rather than spelled out by each row.
///
/// None of this describes a member. A group holds the *same* rows the tab list
/// draws everywhere else — full height, full favicon, full trailing control —
/// so a member's own geometry comes from `BrowserSidebarTabRowMetrics`. What
/// is left is how far apart the rows stack, and the slim strip above them that
/// names the group.
///
/// The container's insets are deliberately absent here because they are not
/// the container's to choose. Its inset from the sidebar edge, the padding it
/// holds its rows in by, the space it keeps from its neighbours and its corners
/// are the ones a folder uses too, from `BrowserSidebarMetrics`, so a group
/// lines up in the same column as the tabs above and below it. The header's
/// leading inset is the tab row's `contentLeadingInset`, so the count glyph
/// sits in the same column as the member favicons.
struct BrowserSidebarSplitGroupRowMetrics: Equatable, Sendable {
    /// The gap between the header and the first member, and between members.
    ///
    /// A pointer shell stacks them flush: the rows are a fixed band each, and
    /// the container's own tint is what says they belong together. A touch
    /// shell separates them, because a finger aiming at one row in a stack of
    /// four wants to see where each one ends.
    let memberSpacing: CGFloat

    /// The header owns group actions now, including its ellipsis menu. Touch
    /// shells therefore give it a full native hit target while pointer shells
    /// keep the compact sidebar rhythm.
    let headerHeight: CGFloat

    let headerGlyphSize: CGFloat

    let headerSpacing: CGFloat

    /// A pointer shell: members flush against one another under a compact
    /// header strip.
    static let pointer = BrowserSidebarSplitGroupRowMetrics(
        memberSpacing: 0,
        headerHeight: 30,
        headerGlyphSize: 16,
        headerSpacing: 7
    )

    /// A touch shell: the same container, with the members held apart and a
    /// slightly taller header carrying a slightly larger glyph, both read at
    /// arm's length rather than at a desk.
    static let touch = BrowserSidebarSplitGroupRowMetrics(
        memberSpacing: CrestSpacing.extraExtraSmall,
        headerHeight: 44,
        headerGlyphSize: 20,
        headerSpacing: 8
    )
}
