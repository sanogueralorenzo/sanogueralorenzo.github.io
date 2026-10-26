import AppKit
import SwiftUI

/// Reviewing what one browser brings, one Space at a time: the browser's
/// sidebar on the left, Crest's on the right wearing the look setup chose,
/// and between them what the Space brings along.
struct BrowserOnboardingReviewPage: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let flow: BrowserOnboardingFlow
    @Binding var customizationSpaceID: UUID?
    let back: BrowserOnboardingBackAction

    var body: some View {
        if let setupReview = flow.review,
            let review = flow.selectedReview(id: setupReview.shownSpaceID)
        {
            let spaces = flow.reviewSpaces
            VStack(spacing: 0) {
                BrowserOnboardingReviewHeader(
                    icon: sourceIcon,
                    title: setupReview.title,
                    progressLabel: flow.reviewProgressLabel(for: review)
                )
                .disabled(flow.isCommittingImport)

                // The browser's Spaces stack under one another, one page each,
                // so moving between them reads as moving through that browser.
                ZStack(alignment: .trailing) {
                    ScrollView(.vertical) {
                        LazyVStack(spacing: 0) {
                            ForEach(spaces) { item in
                                BrowserOnboardingReviewSpacePage(
                                    flow: flow,
                                    application: setupReview.source,
                                    spaces: spaces,
                                    review: item,
                                    leftOut: setupReview.leftOut,
                                    customize: { customizationSpaceID = item.id }
                                )
                                .containerRelativeFrame(.vertical)
                                .id(item.id)
                            }
                        }
                        .scrollTargetLayout()
                    }
                    .scrollPosition(id: shownSpaceID, anchor: .top)
                    .scrollTargetBehavior(.viewAligned)
                    .scrollIndicators(.hidden)

                    BrowserOnboardingReviewSpaceStepper(spaces: spaces, selectedSpaceID: setupReview.shownSpaceID)
                }
                .disabled(flow.isCommittingImport)

                BrowserOnboardingFooter(back: back, isBackDisabled: flow.isCommittingImport) {
                    HStack(spacing: 22) {
                        if let failure = flow.failure?.message {
                            Label {
                                BrowserOnboardingFailureMessage(message: failure)
                            } icon: {
                                Image(systemName: "exclamationmark.triangle.fill")
                            }
                            .font(CrestTypography.sans(12, weight: .medium))
                            .foregroundStyle(.red)
                            .lineLimit(2)
                            .accessibilityIdentifier("onboarding-workflow-error")
                        } else if let summary = flow.reviewSummary() {
                            Text(summary)
                                .font(CrestTypography.sans(13, weight: .medium))
                                .foregroundStyle(CrestBrandTheme.textDisplay.opacity(0.7))
                        }
                        BrowserOnboardingContinueButton(reviewActionTitle(in: setupReview)) {
                            advanceReviewOrImport(setupReview)
                        }
                        .disabled(
                            flow.isCommittingImport || (setupReview.showsLastSpace && !setupReview.hasIncludedSpaces)
                        )
                        .accessibilityIdentifier(
                            setupReview.showsLastSpace ? "onboarding-confirm-import" : "onboarding-review-next-space")
                    }
                }
            }
        } else {
            ContentUnavailableView(
                "Nothing to Review",
                systemImage: "checklist.unchecked",
                description: Text("Choose a browser to build an import review.")
            )
        }
    }

    private var sourceIcon: NSImage? {
        flow.review.flatMap { flow.offeredSource($0.source) }?.icon
    }

    /// The Space the person is looking at, which setup holds.
    private var shownSpaceID: Binding<UUID?> {
        Binding(get: { flow.shownReviewSpaceID }, set: { flow.shownReviewSpaceID = $0 })
    }

    private func show(_ spaceID: UUID) {
        withAnimation(motion(CrestMotion.onboardingProgress)) {
            flow.shownReviewSpaceID = spaceID
        }
    }

    private func reviewActionTitle(in review: SetupImportReview) -> Text {
        if flow.isCommittingImport { return Text("Importing…") }
        return review.showsLastSpace ? Text(flow.importReviewActionTitle) : Text("Next Space")
    }

    private func advanceReviewOrImport(_ review: SetupImportReview) {
        if !review.showsLastSpace, let nextID = review.nextSpaceID {
            show(nextID)
        } else {
            flow.commitReviewedImport()
        }
    }

    private func motion(_ animation: Animation) -> Animation? {
        animation.unlessReducingMotion(reduceMotion)
    }
}

/// The browser under review, and which of its Spaces this is.
private struct BrowserOnboardingReviewHeader: View {
    let icon: NSImage?
    let title: String
    let progressLabel: String

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            if let icon {
                Image(nsImage: icon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 40, height: 40)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Review \(title)")
                    .font(CrestTypography.display(30))
                    .foregroundStyle(CrestBrandTheme.textDisplay)
                    .lineLimit(1)
                    .accessibilityAddTraits(.isHeader)
                Text(progressLabel)
                    .font(CrestTypography.sans(12, weight: .semibold))
                    .foregroundStyle(CrestBrandTheme.textDisplay.opacity(0.6))
            }
            Spacer(minLength: 20)
        }
        .padding(.horizontal, BrowserOnboardingStageMetrics.pageInset)
        .padding(.top, 8)
        .padding(.bottom, 16)
    }
}

/// Where the shown Space stands among the browser's, down the right edge.
private struct BrowserOnboardingReviewSpaceStepper: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let spaces: [BrowserImportSpaceReview]
    let selectedSpaceID: UUID?

    var body: some View {
        VStack(spacing: 12) {
            ForEach(spaces) { item in
                let isCurrent = item.id == selectedSpaceID
                Capsule(style: .continuous)
                    .fill(isCurrent ? CrestBrandPalette.butter : CrestBrandPalette.paper.opacity(0.3))
                    .frame(width: isCurrent ? 8 : 6, height: isCurrent ? 32 : 6)
                    .animation(
                        CrestMotion.onboardingProgress.unlessReducingMotion(reduceMotion), value: selectedSpaceID
                    )
                    .accessibilityLabel(item.sourceSpace.settings.name)
                    .accessibilityValue(isCurrent ? "Current Space" : "Space in review")
            }
        }
        .padding(.trailing, BrowserOnboardingStageMetrics.inset)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Space review progress")
    }
}

/// What an import leaves out, behind a count: each profile or Space the
/// browser held that Crest cannot bring, with why.
struct BrowserOnboardingReviewLeftOutMenu: View {
    let leftOut: [ImportLeftOut]

    var body: some View {
        Menu {
            ForEach(Array(leftOut.enumerated()), id: \.offset) { _, item in
                Section(item.name) {
                    Text(item.reason.explanation)
                }
            }
        } label: {
            Label {
                Text(BrowserOnboardingSummary.leftOutCount(leftOut.count))
            } icon: {
                Image(systemName: "info.circle")
            }
            .font(CrestTypography.sans(12, weight: .semibold))
            .foregroundStyle(CrestBrandTheme.textDisplay.opacity(0.6))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityHint("Shows what the import leaves out and why")
    }
}
