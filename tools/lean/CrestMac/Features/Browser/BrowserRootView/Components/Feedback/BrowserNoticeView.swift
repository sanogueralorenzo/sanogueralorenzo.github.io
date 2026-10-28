import SwiftUI

struct BrowserNoticeView: View {
    let notice: BrowserNotice

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        HStack(spacing: CrestSpacing.medium) {
            Label(notice.message, systemImage: notice.systemImage)
                .lineLimit(2)
                .multilineTextAlignment(.center)
            if let action = notice.action {
                Button(action.title, action: action.perform)
                    .buttonStyle(.borderless)
                    .accessibilityIdentifier("notice-action")
            }
        }
        .font(.callout.weight(.semibold))
        .padding(
            .horizontal,
            BrowserRootMetrics.noticeHorizontalPadding
        )
        .frame(minHeight: BrowserRootMetrics.noticeHeight)
        .frame(maxWidth: BrowserRootMetrics.noticeMaximumWidth)
        .fixedSize(horizontal: false, vertical: true)
        .glassEffect(.regular, in: .rect(cornerRadius: BrowserRootMetrics.noticeHeight / 2))
        .shadow(
            color: .black.opacity(
                reduceTransparency ? 0 : CrestOpacity.controlShadow
            ),
            radius: BrowserRootMetrics.noticeShadowRadius,
            y: BrowserRootMetrics.noticeShadowYOffset
        )
        .frame(
            maxWidth: .infinity,
            maxHeight: .infinity,
            alignment: .top
        )
        .padding(.top, BrowserRootMetrics.noticeTopInset)
        .allowsHitTesting(notice.action != nil)
        .accessibilityElement(children: notice.action == nil ? .combine : .contain)
        .accessibilityAddTraits(notice.action == nil ? .isStaticText : [])
        .transition(
            reduceMotion
                ? .opacity
                : .move(edge: .top).combined(with: .opacity)
        )
        .zIndex(BrowserRootMetrics.feedbackZIndex)
    }
}

#if DEBUG
    #Preview("Component") {
        BrowserNoticeView(notice: .urlCopied).padding().frame(width: 320, height: 150)
    }
#endif
