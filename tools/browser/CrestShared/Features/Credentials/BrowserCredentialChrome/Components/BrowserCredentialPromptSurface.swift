import SwiftUI

/// The surface every credential prompt is drawn on.
///
/// A pointer shell floats a rounded, stroked, lifted panel over the page; a
/// touch shell runs a band across the content and closes it with a divider.
/// That, and how much width the prompt may claim, is the whole of the
/// difference — the padding, the material, and the accessibility container are
/// the same either way.
struct BrowserCredentialPromptSurface<Content: View>: View {
    let accessibilityLabel: Text
    let accessibilityIdentifier: String
    let width: BrowserCredentialPromptWidth
    let metrics: BrowserCredentialPromptMetrics
    let content: Content

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    init(
        accessibilityLabel: Text,
        accessibilityIdentifier: String,
        width: BrowserCredentialPromptWidth,
        metrics: BrowserCredentialPromptMetrics,
        @ViewBuilder content: () -> Content
    ) {
        self.accessibilityLabel = accessibilityLabel
        self.accessibilityIdentifier = accessibilityIdentifier
        self.width = width
        self.metrics = metrics
        self.content = content()
    }

    var body: some View {
        content
            .padding(.horizontal, metrics.horizontalPadding)
            .padding(.vertical, metrics.verticalPadding)
            .frame(
                minWidth: minimumWidth,
                maxWidth: maximumWidth,
                alignment: contentAlignment
            )
            .background { surfaceBackground }
            .overlay(alignment: .bottom) { surfaceEdge }
            .shadow(
                color: .black.opacity(shadowOpacity),
                radius: BrowserCredentialPromptMetrics.shadowRadius,
                y: BrowserCredentialPromptMetrics.shadowOffset
            )
            .accessibilityElement(children: .contain)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityIdentifier(accessibilityIdentifier)
    }

    @ViewBuilder
    private var surfaceBackground: some View {
        switch metrics.surfaceStyle {
        case .panel:
            CrestSurfaceLayer(
                shape: RoundedRectangle(
                    cornerRadius: BrowserCredentialPromptMetrics.cornerRadius,
                    style: .continuous
                )
            )
        case .band:
            CrestSurfaceLayer(shape: Rectangle())
        }
    }

    /// What closes the surface off from the page: a panel is outlined all the
    /// way round, a band only along the edge it meets the page on.
    @ViewBuilder
    private var surfaceEdge: some View {
        switch metrics.surfaceStyle {
        case .panel:
            RoundedRectangle(
                cornerRadius: BrowserCredentialPromptMetrics.cornerRadius,
                style: .continuous
            )
            .strokeBorder(
                .separator,
                lineWidth: BrowserCredentialPromptMetrics.strokeWidth
            )
        case .band:
            Divider()
        }
    }

    private var shadowOpacity: Double {
        guard metrics.surfaceStyle == .panel, !reduceTransparency else {
            return 0
        }
        return BrowserCredentialPromptMetrics.shadowOpacity
    }

    private var minimumWidth: CGFloat? {
        guard case .fixed(let width) = width else { return nil }
        return width
    }

    private var maximumWidth: CGFloat? {
        switch width {
        case .fixed(let width):
            width
        case .bounded(let width):
            width
        case .flexible:
            .infinity
        }
    }

    private var contentAlignment: Alignment {
        width == .flexible ? .leading : .center
    }
}
