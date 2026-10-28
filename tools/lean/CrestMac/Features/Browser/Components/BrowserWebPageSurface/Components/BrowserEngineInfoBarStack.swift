import SwiftUI

/// The engine's bars for this page, stacked at its top edge.
struct BrowserEngineInfoBarStack: View {
    let page: BrowserPage
    /// Where a sharing bar leads: the tab at the other end of the sharing.
    var goToSharingCounterpart: (() -> Void)? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: BrowserWebPageSurfaceMetrics.infoBarSpacing) {
            ForEach(page.visibleEngineInfoBars) { bar in
                BrowserEngineInfoBarRow(
                    bar: bar, minimize: { page.minimize(bar) },
                    open: bar.isMinimizable ? goToSharingCounterpart : nil
                ) { response in
                    page.respond(to: bar, with: response)
                }
                .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(BrowserWebPageSurfaceMetrics.overlayPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(reduceMotion ? nil : CrestMotion.feedbackPresentation, value: page.visibleEngineInfoBars)
    }
}

private struct BrowserEngineInfoBarRow: View {
    let bar: BrowserEngineInfoBar
    let minimize: () -> Void
    /// What clicking the bar's message does, when it leads somewhere.
    let open: (() -> Void)?
    let respond: (BrowserEngineInfoBar.Response) -> Void

    @ViewBuilder private var message: some View {
        let text = Text(bar.message)
            .font(.callout)
            .lineLimit(3)
            .frame(maxWidth: .infinity, alignment: .leading)
        if let open {
            Button(action: open) {
                text.contentShape(.rect)
            }
            .buttonStyle(.plain)
            .help(
                Text(
                    "Go to the other tab",
                    comment: "Tooltip on a sharing bar's message that shows the tab at the other end."))
        } else {
            text
        }
    }

    var body: some View {
        HStack(spacing: BrowserWebPageSurfaceMetrics.infoBarSpacing) {
            Image(systemName: "info.circle")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            message
            if !bar.cancelTitle.isEmpty {
                Button(bar.cancelTitle) { respond(.cancel) }
            }
            if !bar.acceptTitle.isEmpty {
                Button(bar.acceptTitle) { respond(.accept) }
                    .buttonStyle(.borderedProminent)
            }
            if bar.isMinimizable {
                Button(action: minimize) {
                    Image(systemName: "chevron.up")
                }
                .buttonStyle(
                    CrestChromeButtonStyle(
                        controlSize: CGSize(
                            width: BrowserWebPageSurfaceMetrics.infoBarMinimizeControlSize,
                            height: BrowserWebPageSurfaceMetrics.infoBarMinimizeControlSize))
                )
                .help(
                    Text("Hide until you come back to this tab", comment: "Tooltip on a sharing bar's minimize button.")
                )
                .accessibilityLabel(
                    Text("Minimize", comment: "Accessibility label for a sharing bar's minimize button."))
            }
            if bar.isCloseable {
                Button {
                    respond(.dismiss)
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(Text("Dismiss"))
            }
        }
        .controlSize(.small)
        .padding(.horizontal, BrowserWebPageSurfaceMetrics.infoBarHorizontalPadding)
        .padding(.vertical, BrowserWebPageSurfaceMetrics.infoBarVerticalPadding)
        .frame(maxWidth: BrowserWebPageSurfaceMetrics.infoBarMaximumWidth)
        .glassEffect(.regular, in: .rect(cornerRadius: BrowserWebPageSurfaceMetrics.infoBarCornerRadius))
        .accessibilityElement(children: .contain)
    }
}
