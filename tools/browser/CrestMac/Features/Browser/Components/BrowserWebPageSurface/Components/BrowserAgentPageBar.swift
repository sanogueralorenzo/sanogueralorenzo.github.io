import SwiftUI

/// The bar a page wears while an agent uses its tab: the agent's mark in its
/// colour, who uses the tab, and Stop, which keeps the agent out of the tab
/// for as long as it stays connected. It sits where the engine's own bars do,
/// in the same glass.
struct BrowserAgentPageBar: View {
    let session: AgentSessionState
    let stop: () -> Void

    var body: some View {
        HStack(spacing: BrowserWebPageSurfaceMetrics.infoBarSpacing) {
            Image(systemName: "sparkles")
                .foregroundStyle((session.color ?? .agentDefault).color)
                .accessibilityHidden(true)
            Text("\(session.name) is using this tab", comment: "The bar on a page an agent uses.")
                .font(.callout)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(String(localized: "Stop", comment: "Stops the agent using a tab."), action: stop)
        }
        .controlSize(.small)
        .padding(.horizontal, BrowserWebPageSurfaceMetrics.infoBarHorizontalPadding)
        .padding(.vertical, BrowserWebPageSurfaceMetrics.infoBarVerticalPadding)
        .frame(maxWidth: BrowserWebPageSurfaceMetrics.infoBarMaximumWidth)
        .glassEffect(.regular, in: .rect(cornerRadius: BrowserWebPageSurfaceMetrics.infoBarCornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: BrowserWebPageSurfaceMetrics.infoBarCornerRadius)
                .strokeBorder((session.color ?? .agentDefault).color, lineWidth: 1)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("agent-page-bar")
    }
}
