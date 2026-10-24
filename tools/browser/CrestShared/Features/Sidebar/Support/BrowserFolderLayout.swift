import CoreGraphics

/// How far a saved folder and everything inside it step in per nesting level.
///
/// One formula, on every shell: the folder's own header and the rows it holds
/// advance by the same step, so a nested group keeps the rhythm of the folder
/// that holds it instead of drifting out of it. The step is the container
/// padding every folder and Split View holds its contents in by, so each level
/// sits exactly that padding inside the container around it.
enum BrowserFolderLayout {
    static let nestingIndent = BrowserSidebarMetrics.containerPadding

    /// How far a folder's surface sits from the sidebar's leading edge: the
    /// layer inset every top-level layer keeps, plus one step per folder that
    /// holds it. A folder's bounds start at that edge however deep it is.
    static func surfaceLeadingInset(depth: Int) -> CGFloat {
        BrowserSidebarMetrics.layerInset + nestingIndent * CGFloat(max(0, depth))
    }

    /// How far a row *inside* a folder sits from the sidebar's leading edge:
    /// one step for the folder itself, plus one per level above it. Tab rows
    /// and stacked split-group rows share it so a group never breaks the
    /// nesting rhythm.
    static func rowLeadingInset(depth: Int) -> CGFloat {
        nestingIndent * CGFloat(max(0, depth) + 1)
    }

    /// How far the folder header's own content sits from the leading edge of
    /// the space the folder's padding leaves.
    ///
    /// The base is the tab row's `contentLeadingInset` rather than a number of
    /// its own, so the folder's icon lands in the same column as the favicons
    /// of the rows it holds — the same reason a split group's header reads its
    /// leading inset from the tab row profile.
    static func headerLeadingInset(
        depth: Int,
        tabRowMetrics: BrowserSidebarTabRowMetrics
    ) -> CGFloat {
        tabRowMetrics.contentLeadingInset
            + nestingIndent * CGFloat(max(0, depth))
    }
}
