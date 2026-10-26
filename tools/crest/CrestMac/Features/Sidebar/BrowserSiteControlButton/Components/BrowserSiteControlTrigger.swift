import SwiftUI

struct BrowserSiteControlTrigger: View {
    @Binding var isPresented: Bool
    let blockedPopupNotice: BrowserBlockedPopupNotice?

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "slider.horizontal.3")
                    .font(
                        .system(
                            size: BrowserTabTrailingControlMetrics.pointer.glyphSize,
                            weight: .medium
                        )
                    )
                if blockedPopupNotice != nil {
                    Circle()
                        .fill(.orange)
                        .frame(width: 7, height: 7)
                        .overlay {
                            Circle().stroke(.background, lineWidth: 1)
                        }
                        .offset(x: 2, y: -1)
                        .accessibilityHidden(true)
                }
            }
            .frame(
                width: BrowserSiteControlMetrics.triggerSize.width,
                height: BrowserSiteControlMetrics.triggerSize.height
            )
            .contentShape(.rect)
        }
        .buttonStyle(
            CrestChromeButtonStyle(
                controlSize: BrowserSiteControlMetrics.triggerSize
            )
        )
        .foregroundStyle(
            blockedPopupNotice == nil ? Color.secondary : Color.orange
        )
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(accessibilityHint)
        .accessibilityIdentifier("browser-site-controls")
        .help(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        guard let blockedPopupNotice else { return "Site Controls" }
        return blockedPopupNotice.chromeAccessibilityLabel(
            surfaceName: "Site Controls"
        )
    }

    private var accessibilityHint: String {
        guard blockedPopupNotice != nil else {
            return "Opens controls for this website"
        }
        return "Opens the Automatic Pop-ups permission and retry guidance"
    }
}
