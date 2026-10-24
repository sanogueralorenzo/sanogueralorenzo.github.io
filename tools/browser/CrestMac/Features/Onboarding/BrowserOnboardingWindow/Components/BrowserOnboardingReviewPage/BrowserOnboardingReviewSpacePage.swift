import SwiftUI

/// One reviewed Space: the browser's sidebar, what comes along, and Crest's
/// sidebar as it would be.
struct BrowserOnboardingReviewSpacePage: View {
    let flow: BrowserOnboardingFlow
    let application: ImportSource?
    let spaces: [BrowserImportSpaceReview]
    let review: BrowserImportSpaceReview
    /// What the browser held that the import cannot bring, and why.
    let leftOut: [ImportLeftOut]
    let customize: () -> Void

    var body: some View {
        GeometryReader { geometry in
            let layout = BrowserOnboardingReviewLayout(width: geometry.size.width)
            columns(layout)
                .padding(.horizontal, layout.inset)
                .padding(.bottom, 16)
        }
    }

    private func columns(_ layout: BrowserOnboardingReviewLayout) -> some View {
        let analysis = flow.reviewAnalysis()
        return HStack(alignment: .top, spacing: layout.spacing) {
            VStack(alignment: .leading, spacing: 10) {
                BrowserOnboardingReviewColumnLabel(title: "From \(flow.review?.title ?? application?.title ?? "")")
                BrowserSourceImportPreview(
                    application: application,
                    review: review,
                    overflowTabIDs: analysis.overflowTabIDs,
                    duplicateTabIDs: analysis.duplicateTabIDs,
                    duplicateDestinationName: flow.duplicateDestinationName(for: review),
                    setIncluded: { tabID, isIncluded in flow.setIncluded(tabID, isIncluded, in: review.id) },
                    setSectionIncluded: { tabIDs, isIncluded in flow.setIncluded(tabIDs, isIncluded, in: review.id) },
                    setPlacement: { tabID, placement in flow.setPlacement(placement, for: tabID, in: review.id) },
                    extensionIcons: flow.extensionIcons,
                    setExtensionIncluded: { extensionID, isIncluded in
                        flow.setExtensionIncluded(extensionID, isIncluded, in: review.id)
                    },
                    title: flow.review?.title
                )
                .frame(maxHeight: .infinity)
                Text("Click anything to leave it out.")
                    .font(CrestTypography.sans(12, weight: .medium))
                    .foregroundStyle(CrestBrandTheme.textDisplay.opacity(0.55))
            }
            .frame(width: layout.sidebarWidth)

            VStack(spacing: 20) {
                Spacer(minLength: 0)
                BrowserOnboardingReviewChecklist(
                    flow: flow, application: application, review: review, analysis: analysis)
                if !leftOut.isEmpty {
                    BrowserOnboardingReviewLeftOutMenu(leftOut: leftOut)
                }
                Spacer(minLength: 0)
            }
            .frame(width: BrowserOnboardingReviewLayout.checklistWidth)

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    BrowserOnboardingReviewColumnLabel(title: "Into Crest")
                    Spacer()
                    Button("Customize", systemImage: "paintpalette", action: customize)
                        .buttonStyle(.crestTertiary)
                        .disabled(!review.isIncluded)
                        .accessibilityIdentifier("onboarding-review-customize")
                }
                BrowserCrestImportPreview(
                    space: flow.previewDestinationSpace(for: review),
                    favicons: flow.previewFavicons,
                    sourceName: flow.review?.title ?? application?.title ?? "Browser",
                    isSpaceIncluded: review.isIncluded,
                    matchedTabIDs: analysis.matchedTabIDs(for: review.id),
                    extensions: review.record.broughtExtensions,
                    extensionIcons: flow.extensionIcons
                )
                .frame(maxHeight: .infinity)
            }
            .frame(width: layout.sidebarWidth)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// The name over a column of the review.
private struct BrowserOnboardingReviewColumnLabel: View {
    let title: LocalizedStringKey

    var body: some View {
        Text(title)
            .font(CrestTypography.sans(11, weight: .bold))
            .tracking(1.4)
            .textCase(.uppercase)
            .foregroundStyle(CrestBrandTheme.textDisplay.opacity(0.6))
            .frame(height: 20)
    }
}

/// How the review's columns share a stage `width` wide: the checklist keeps
/// its width, the two sidebars share the rest within what a sidebar draws
/// well, and the insets and gaps close up on a narrow stage.
struct BrowserOnboardingReviewLayout {
    static let checklistWidth: CGFloat = 300
    private static let widestSidebar: CGFloat = 380
    private static let narrowestSidebar: CGFloat = 250

    let inset: CGFloat
    let spacing: CGFloat
    let sidebarWidth: CGFloat

    init(width: CGFloat) {
        let wide = width >= BrowserOnboardingStageMetrics.wideStageWidth
        inset = BrowserOnboardingStageMetrics.pageInset(for: width)
        spacing = wide ? 40 : 24
        let shared = (width - inset * 2 - Self.checklistWidth - spacing * 2) / 2
        sidebarWidth = min(Self.widestSidebar, max(Self.narrowestSidebar, shared))
    }
}
