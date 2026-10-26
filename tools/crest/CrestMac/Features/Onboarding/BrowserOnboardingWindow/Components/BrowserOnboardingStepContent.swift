import SwiftUI

/// The page for the step setup is on. Back leads where the core says, or
/// closes setup where it leads nowhere.
struct BrowserOnboardingStepContent: View, BrowserOnboardingPages {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let cloudSync: BrowserCloudSyncController
    let progress: BrowserOnboardingProgressStore
    let flow: BrowserOnboardingFlow
    let cloudWait: BrowserOnboardingCloudWait
    @Binding var selectedManualSpaceID: UUID?
    @Binding var customizationSpaceID: UUID?
    let close: () -> Void
    let openCrest: () -> Void

    var body: some View {
        flow.step.page(in: self)
    }

    // MARK: - Pages

    func welcomePage() -> some View {
        BrowserOnboardingWelcomePage(
            action: BrowserOnboardingWelcomeAction(
                flow: flow.state, cloudPhase: cloudSync.phase, wait: cloudWait.stage,
                forcesSetup: progress.forcesSetup),
            hasCompletedSetup: progress.hasCompletedSetup,
            hasDisposableSeedState: flow.hasDisposableSeedState,
            continueSetup: continueSetup,
            setUpWithoutCloud: {
                cloudWait.setUpWithoutCloud()
                continueSetup()
            },
            openCrest: openCrest
        )
    }

    func lookPage() -> some View {
        BrowserOnboardingLookPage(
            look: flow.look,
            choose: { look in
                withAnimation(motion(CrestMotion.onboardingBackdrop)) { flow.chooseLook(look) }
            },
            back: back,
            continueSetup: continueSetup
        )
    }

    /// Setup on the Mac has no pages for the feature tour.
    func featureSpacesPage() -> some View { EmptyView() }

    func featureTabsPage() -> some View { EmptyView() }

    func featureSyncPage() -> some View { EmptyView() }

    func importBrowserPage() -> some View {
        BrowserOnboardingImportPage(
            sources: flow.offeredSources,
            isSelected: flow.isSelected,
            hasScanned: flow.hasScanned,
            unlistedCount: flow.unlistedSources.count,
            isReading: flow.isReading,
            isLocked: flow.isImportSelectionLocked,
            failure: flow.failure?.message,
            accessLabel: flow.importAccessLabel,
            toggleSelection: flow.toggleSelection,
            scanForMore: flow.scanForMore,
            beginManualSetup: beginManualSetup,
            continueImport: flow.continueImportQueue,
            cancelRead: flow.cancelImportRead,
            back: back
        )
        .id(flow.step)
    }

    func reviewPage() -> some View {
        BrowserOnboardingReviewPage(
            flow: flow,
            customizationSpaceID: $customizationSpaceID,
            back: back
        )
    }

    func manualSetupPage() -> some View {
        BrowserOnboardingManualSetupPage(
            flow: flow,
            selectedSpaceID: $selectedManualSpaceID,
            back: back,
            advance: { transition(to: .complete) }
        )
    }

    /// The Spaces setup is about to make, or the workspace's once it has.
    func completePage() -> some View {
        BrowserOnboardingCompletionPage(
            spaces: flow.manualSetup.spaces.isEmpty
                ? flow.destinationSpaces.map(\.identity) : flow.manualSetup.previewSpaces,
            summary: flow.completionSummary,
            opensGuide: flow.state?.opensGuide == true,
            back: flow.state?.backStep == nil ? nil : back,
            openCrest: openCrest
        )
    }

    // MARK: - Navigation

    /// What Back does from the step: the step the core names, or closing.
    private var back: BrowserOnboardingBackAction {
        guard let step = flow.state?.backStep else { return BrowserOnboardingBackAction(closes: true, action: close) }
        return BrowserOnboardingBackAction(closes: false, action: { transition(to: step) })
    }

    private func continueSetup() {
        if let next = flow.state?.nextStep { transition(to: next) }
    }

    private func beginManualSetup() {
        flow.beginManualSetup()
        flow.manualSetup.repairSelection($selectedManualSpaceID)
    }

    private func transition(to step: SetupStep) {
        withAnimation(motion(CrestMotion.onboardingStep)) {
            flow.show(step)
        }
        if step == .manualSetup { flow.manualSetup.repairSelection($selectedManualSpaceID) }
    }

    private func motion(_ animation: Animation) -> Animation? {
        animation.unlessReducingMotion(reduceMotion)
    }
}

/// What a page's Back button does: go back a step, or close setup where the
/// entry did not pass through one.
struct BrowserOnboardingBackAction {
    /// Whether Back closes setup, which the button then says.
    let closes: Bool
    let action: () -> Void
}
