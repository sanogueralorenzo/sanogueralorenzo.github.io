import SwiftUI

/// The last page: the Spaces setup made as banners, and the way into Crest.
struct BrowserOnboardingCompletionPage: View {
    /// The Spaces setup is about to make, or made.
    let spaces: [BrowserSpaceIdentity]
    /// What setup did, once it has.
    let summary: LocalizedStringResource?
    /// Whether the Getting Started guide opens next.
    let opensGuide: Bool
    let back: BrowserOnboardingBackAction?
    let openCrest: () -> Void

    private var shown: [BrowserSpaceIdentity] { Array(spaces.prefix(3)) }

    var body: some View {
        GeometryReader { geometry in
            let size = windowSize(in: geometry.size)
            VStack(spacing: 0) {
                Spacer()
                HStack(alignment: .top, spacing: BrowserOnboardingCompletionMetrics.spacing) {
                    ForEach(shown) { space in
                        BrowserOnboardingWindowPreview(branding: space.branding, symbol: space.symbol, name: space.name)
                        {
                            BrowserSpaceIdentityIcon(identity: space, size: size.height * 0.3)
                                .frame(width: size.height * 0.3, height: size.height * 0.3)
                        }
                        .frame(width: size.width, height: size.height)
                    }
                }
                .padding(.bottom, 56)
                closing
                Spacer()
                if let back {
                    BrowserOnboardingFooter(back: back) { EmptyView() }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// The size each window takes: the stage's width shared between them,
    /// at the browser window's own proportions, as tall as the stage leaves
    /// room for over the closing.
    private func windowSize(in stage: CGSize) -> CGSize {
        let count = CGFloat(max(shown.count, 1))
        let available = stage.width - BrowserOnboardingStageMetrics.pageInset * 2
        let width = min(
            (available - BrowserOnboardingCompletionMetrics.spacing * (count - 1)) / count,
            BrowserOnboardingCompletionMetrics.maximumWindowWidth)
        let height = min(width / BrowserOnboardingCompletionMetrics.windowAspect, stage.height * 0.52)
        return CGSize(width: height * BrowserOnboardingCompletionMetrics.windowAspect, height: height)
    }

    private var closing: some View {
        VStack(spacing: 0) {
            BrowserOnboardingHeadline("Ready")
            BrowserOnboardingContinueButton("Open Crest", action: openCrest)
                .controlSize(.large)
                .padding(.top, 18)
                .accessibilityIdentifier("onboarding-open-crest")
            Text(detail)
                .font(CrestTypography.sans(12, weight: .medium))
                .foregroundStyle(CrestBrandTheme.textDisplay.opacity(0.6))
                .padding(.top, 14)
        }
    }

    private var detail: String {
        var parts: [String] = []
        if let summary { parts.append(String(localized: summary)) }
        if opensGuide { parts.append(String(localized: "Getting Started opens next.")) }
        return parts.joined(separator: " ")
    }
}

enum BrowserOnboardingCompletionMetrics {
    static let spacing: CGFloat = 32
    static let maximumWindowWidth: CGFloat = 720
    /// The browser window's own proportions, as it opens: 1440 by 900.
    static let windowAspect: CGFloat = 1.6
}
