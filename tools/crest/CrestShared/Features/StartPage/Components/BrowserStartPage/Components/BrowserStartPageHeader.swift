import SwiftUI

/// The mark, the title, and — in a private session — the notice that says what
/// this window is not keeping.
///
/// The three sit in a `Group` so the enclosing stack spaces them itself, which
/// is what keeps the header's rhythm the same as the gap to the palette below.
struct BrowserStartPageHeader: View {
    let isPrivateBrowsing: Bool
    let layout: BrowserStartPageLayout
    /// The appearance the text reads its tone from. `nil` inherits the
    /// environment's, which is what a shell that draws no branding behind the
    /// header wants.
    let colorScheme: ColorScheme?

    @ViewBuilder
    var body: some View {
        if let colorScheme {
            content
                .environment(\.colorScheme, colorScheme)
        } else {
            content
        }
    }

    @ViewBuilder
    private var content: some View {
        CrestStartPageMark()
            .frame(width: layout.markSize, height: layout.markSize)
            .accessibilityHidden(true)
        Text("Start Page")
            .font(.largeTitle.weight(.semibold))
            .foregroundStyle(.primary)
            .multilineTextAlignment(.center)

        if isPrivateBrowsing {
            BrowserStartPagePrivateBrowsingNotice(
                spacing: layout.privateNoticeSpacing
            )
        }
    }
}

#if DEBUG
    #Preview("Standard and private") {
        VStack(spacing: 32) {
            BrowserStartPageHeader(isPrivateBrowsing: false, layout: .macOSPage, colorScheme: nil)
            BrowserStartPageHeader(isPrivateBrowsing: true, layout: .mobileCompactPage, colorScheme: nil)
        }.padding().frame(width: 380)
    }
#endif
