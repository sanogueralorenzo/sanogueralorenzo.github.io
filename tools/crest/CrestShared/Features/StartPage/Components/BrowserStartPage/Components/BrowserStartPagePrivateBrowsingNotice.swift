import SwiftUI

/// What a private session tells the reader it is not keeping.
struct BrowserStartPagePrivateBrowsingNotice: View {
    let spacing: CGFloat

    var body: some View {
        VStack(spacing: spacing) {
            Label(
                "Private Browsing",
                systemImage: BrowserPrivateBrowsingAppearance.symbol
            )
            .font(.headline)
            .foregroundStyle(.primary)
            Text(
                "Crest does not save this session or use Crest Passwords. Website data stays in memory only."
            )
            .font(.callout)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("private-browsing-notice")
    }
}

#if DEBUG
    #Preview("Component") {
        BrowserStartPagePrivateBrowsingNotice(spacing: 6).padding().frame(width: 360)
    }
#endif
