import SwiftUI

struct BrowserOnboardingWindowContent: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let request: BrowserOnboardingRequest
    let cloudSync: BrowserCloudSyncController
    let progress: BrowserOnboardingProgressStore
    let flow: BrowserOnboardingFlow
    let cloudWait: BrowserOnboardingCloudWait
    @Binding var selectedManualSpaceID: UUID?
    @Binding var customizationSpaceID: UUID?
    let close: () -> Void
    let openCrest: () -> Void

    /// Which template's field the welcome shows, cycling through them all.
    @State private var welcomeHouse = 0

    var body: some View {
        BrowserOnboardingStage(step: flow.step, branding: stageBranding) {
            VStack(spacing: 0) {
                if let customizationSpaceID, flow.review != nil {
                    BrowserImportSpaceCustomizationView(
                        flow: flow,
                        spaceID: customizationSpaceID,
                        previewSpace: flow.customizationPreviewSpace(
                            customizationSpaceID
                        ),
                        done: { self.customizationSpaceID = nil }
                    )
                } else {
                    BrowserOnboardingStepContent(
                        cloudSync: cloudSync,
                        progress: progress,
                        flow: flow,
                        cloudWait: cloudWait,
                        selectedManualSpaceID: $selectedManualSpaceID,
                        customizationSpaceID: $customizationSpaceID,
                        close: close,
                        openCrest: openCrest
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                if let failure = flow.completionFailure {
                    Text(failure)
                        .foregroundStyle(.red)
                        .padding()
                }
            }
            .disabled(flow.isCompletingSetup)
        }
        .ignoresSafeArea()
        .frame(minWidth: 980, minHeight: 660)
        .tint(CrestBrandTheme.accent)
        .background(BrowserOnboardingWindowConfigurator())
        .task {
            await start()
        }
        .task {
            await cloudWait.run()
        }
        .task(id: flow.step == .welcome) {
            await cycleWelcomeBackdrop()
        }
        .onChange(of: request) { _, newRequest in
            resetTransientState(for: newRequest)
        }
        .onChange(of: flow.step) { _, step in
            if step == .manualSetup { flow.manualSetup.repairSelection($selectedManualSpaceID) }
        }
        .onDisappear(perform: flow.cancelOperations)
        .animation(motion(CrestMotion.onboardingStep), value: flow.state)
    }

    /// The look the stage wears behind the step: on the welcome, the
    /// templates in turn; while a Space is being made or reviewed, that
    /// Space's own; otherwise the look setup chose.
    private var stageBranding: SpaceBranding {
        switch flow.step.kind {
        case .welcome:
            return SpaceHouse.all[welcomeHouse % SpaceHouse.all.count].look
        case .manualSetup:
            return flow.manualSetup.space(selectedManualSpaceID)?.customization.branding ?? flow.look.previewBranding
        case .review:
            guard let review = flow.selectedReview(id: flow.shownReviewSpaceID) else {
                return flow.look.previewBranding
            }
            return flow.previewDestinationSpace(for: review)?.settings.look ?? flow.look.previewBranding
        case .complete:
            return flow.manualSetup.spaces.first?.customization.branding ?? flow.look.previewBranding
        case .look, .featureSpaces, .featureTabs, .featureSync, .importBrowser:
            return flow.look.previewBranding
        }
    }

    private func start() async {
        flow.start()
        flow.discoverInstalledSources()
        flow.manualSetup.repairSelection($selectedManualSpaceID)
    }

    /// Fades the welcome's backdrop from one template's field to the next
    /// while the welcome shows, unless motion is reduced.
    private func cycleWelcomeBackdrop() async {
        guard flow.step == .welcome, !reduceMotion else { return }
        while !Task.isCancelled {
            try? await Task.sleep(for: CrestMotion.onboardingWelcomeHold)
            guard !Task.isCancelled else { return }
            welcomeHouse += 1
        }
    }

    private func resetTransientState(for request: BrowserOnboardingRequest) {
        customizationSpaceID = nil
        withAnimation(motion(CrestMotion.onboardingStep)) {
            flow.reset(for: request)
        }
        selectedManualSpaceID = flow.manualSetup.spaces.first?.spaceID
    }

    private func motion(_ animation: Animation) -> Animation? {
        animation.unlessReducingMotion(reduceMotion)
    }
}
