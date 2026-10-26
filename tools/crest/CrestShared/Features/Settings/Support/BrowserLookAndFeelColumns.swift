import CoreGraphics

/// The two columns of the Look and Feel pane's pinned layout: one window crop
/// pinned beside a scrolling form. Without room for both, each group's own
/// card shows its preview instead.
///
/// The form is the fixed partner: it never grows past the readable width the
/// other panes use, so its controls stay where a reader left them. Everything
/// beyond that goes to the preview, whose page edge simply shows more of the
/// page as the window widens.
struct BrowserLookAndFeelColumns: Equatable {
    // MARK: - Static Variables

    /// The narrowest crop that still shows the whole sidebar and a readable
    /// page edge, plus the narrowest form column that fits a title beside a
    /// segmented control.
    static let previewMinimumWidth: CGFloat = 260
    static let formMinimumWidth: CGFloat = 356
    static let previewLeadingPadding: CGFloat = CrestSpacing.extraExtraLarge
    static let pinnedPreviewMinimumWidth: CGFloat = previewMinimumWidth + formMinimumWidth + previewLeadingPadding
    static let formMaximumWidth: CGFloat = BrowserSettingsLayout.maximumReadableContentWidth

    // MARK: - Variables

    let preview: CGFloat
    let form: CGFloat

    // MARK: - Initializers

    /// How a pane `width` wide shares itself between the pinned preview and
    /// the form, or nil when it has no room for a pinned preview.
    init?(width: CGFloat) {
        guard width >= Self.pinnedPreviewMinimumWidth else { return nil }
        let available = max(0, width - Self.previewLeadingPadding)
        let form = min(Self.formMaximumWidth, max(Self.formMinimumWidth, available - Self.previewMinimumWidth))
        self.preview = max(0, available - form)
        self.form = form
    }
}
