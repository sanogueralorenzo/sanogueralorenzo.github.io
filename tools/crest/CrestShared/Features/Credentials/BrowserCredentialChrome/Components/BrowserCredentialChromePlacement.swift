import SwiftUI

/// Where the credential chrome sits over the page.
///
/// Two arrangements, and the profile picks between them. A band shell keeps the
/// prompt in the place it reserved for chrome and lets the page move under it.
/// A pointer shell puts a fill prompt under the field that asked for it, the
/// way every other password manager on the platform does, and follows the field
/// as the page scrolls beneath it.
///
/// The prompt is handed its profile rather than reading it, because the width
/// of an anchored panel is the field's rather than the shell's, and that has to
/// be decided before the prompt is built.
struct BrowserCredentialChromePlacement<Content: View>: View {
    /// The field the prompt points at, in this shell's points, or `nil` where
    /// there is nothing to point at — no request, no reported rect, or a rect
    /// from a frame whose coordinates say nothing about where the page is.
    let field: CGRect?
    let metrics: BrowserCredentialPromptMetrics
    let content: (BrowserCredentialPromptMetrics) -> Content

    @State private var pageSize = CGSize.zero
    @State private var promptSize = CGSize.zero

    @ViewBuilder
    var body: some View {
        if let field, metrics.anchorsFillPromptToField {
            anchored(to: field)
        } else {
            content(metrics)
                .transition(.move(edge: .top).combined(with: .opacity))
                .padding(metrics.chromeInset)
        }
    }

    private func anchored(to field: CGRect) -> some View {
        let placement = BrowserCredentialPromptPlacement(
            field: field,
            size: promptSize,
            container: pageSize,
            gap: BrowserCredentialPromptMetrics.fieldAnchorGap,
            inset: metrics.chromeInset
        )
        return content(metrics.narrowingFillPrompt(to: anchoredWidth(field)))
            .onGeometryChange(for: CGSize.self) { proxy in
                proxy.size
            } action: { size in
                promptSize = size
            }
            // Held back for the frame it takes to measure the page and the
            // panel, so the panel is never seen in the corner it is measured
            // in on its way to the field.
            .opacity(isMeasured ? 1 : 0)
            .transition(
                .scale(scale: 0.97, anchor: placement.isAboveField ? .bottom : .top)
                    .combined(with: .opacity)
            )
            .offset(x: placement.origin.x, y: placement.origin.y)
            .frame(
                maxWidth: .infinity,
                maxHeight: .infinity,
                alignment: .topLeading
            )
            .onGeometryChange(for: CGSize.self) { proxy in
                proxy.size
            } action: { size in
                pageSize = size
            }
    }

    private var isMeasured: Bool {
        pageSize.width > 0 && promptSize.width > 0
    }

    private func anchoredWidth(_ field: CGRect) -> CGFloat {
        BrowserCredentialPromptPlacement.width(
            field: field,
            container: pageSize,
            minimumWidth: metrics.anchoredFillPromptMinimumWidth ?? field.width,
            maximumWidth: metrics.fillPromptWidth.boundedWidth ?? field.width,
            inset: metrics.chromeInset
        )
    }
}
