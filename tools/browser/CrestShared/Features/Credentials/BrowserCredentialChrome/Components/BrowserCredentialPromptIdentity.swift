import SwiftUI

/// The mark a fill prompt opens with: the site's own icon where the page has
/// one, and the Space's key where it does not.
///
/// The icon is the page's, so it is only shown for a request the page can speak
/// for. A sign-in embedded from somewhere else is named by its own origin on the
/// line beneath, and putting the host page's mark beside that name would say the
/// opposite of what the cross-origin notice says.
struct BrowserCredentialPromptIdentity: View {
    let kind: BrowserCredentialPromptHeaderKind
    let iconData: Data?
    let showsSiteIcon: Bool
    let tint: Color

    @State private var icon = BrowserCredentialSiteIcon()

    var body: some View {
        mark
            .frame(
                width: BrowserCredentialPromptMetrics.headerIdentitySize,
                height: BrowserCredentialPromptMetrics.headerIdentitySize
            )
            .background(
                tint.opacity(
                    BrowserCredentialPromptMetrics.headerIdentityTintOpacity
                ),
                in: .rect(
                    cornerRadius: BrowserCredentialPromptMetrics
                        .headerIdentityCornerRadius,
                    style: .continuous
                )
            )
            .accessibilityHidden(true)
            .task(id: requestedIconData) {
                await loadIcon()
            }
    }

    @ViewBuilder
    private var mark: some View {
        if let image = icon.image(for: requestedIconData) {
            image
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(
                    width: BrowserCredentialPromptMetrics.headerIdentityIconSize,
                    height: BrowserCredentialPromptMetrics.headerIdentityIconSize
                )
                .clipShape(.rect(cornerRadius: CrestRadius.compact / 2))
        } else {
            Image(systemName: kind.symbol)
                .font(
                    .system(
                        size: BrowserCredentialPromptMetrics
                            .headerIdentitySymbolSize,
                        weight: .semibold
                    )
                )
                .foregroundStyle(tint)
        }
    }

    private var requestedIconData: Data? {
        showsSiteIcon ? iconData : nil
    }

    private func loadIcon() async {
        let requested = requestedIconData
        guard let requested else {
            icon.publish(nil, for: nil)
            return
        }
        let decoded = await BrowserFaviconImageDecoder.decode(
            requested,
            maximumPixelSize: BrowserCredentialSiteIcon.maximumPixelSize
        )
        guard !Task.isCancelled, let decoded else { return }
        icon.publish(
            Image(decorative: decoded, scale: BrowserCredentialSiteIcon.scale),
            for: requested
        )
    }
}

/// The last site icon a prompt decoded, and the bytes it was decoded from.
///
/// The bytes are kept beside the image for the same reason a favicon render
/// state keeps its request identity: a decode that lands after the page has
/// moved on is a picture of the wrong site.
@MainActor
struct BrowserCredentialSiteIcon {
    /// Enough pixels for a crisp mark on a 2x display and no more.
    static let maximumPixelSize = 64
    static let scale: CGFloat = 2

    private var iconData: Data?
    private var decoded: Image?

    func image(for iconData: Data?) -> Image? {
        guard let iconData, iconData == self.iconData else { return nil }
        return decoded
    }

    mutating func publish(_ image: Image?, for iconData: Data?) {
        self.iconData = iconData
        decoded = image
    }
}
