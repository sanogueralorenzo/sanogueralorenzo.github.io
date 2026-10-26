import SwiftUI

struct MobileOnboardingCurrentPage: View, BrowserOnboardingPages {
    let context: MobileOnboardingPageContext

    var body: some View {
        context.step.page(in: self)
    }

    // MARK: - Pages

    func welcomePage() -> some View {
        MobileOnboardingWelcomePage(
            action: context.welcomeAction,
            primaryTitle: context.welcomePrimaryTitle,
            status: context.welcomeStatus,
            primaryAction: context.welcomePrimaryAction,
            setupWithoutCloudAction: context.welcomeSetupWithoutCloudAction
        )
    }

    func featureSpacesPage() -> some View {
        MobileOnboardingSpacesFeaturePage(
            previewWidth: context.previewWidth,
            personalSpace: context.personalSpace,
            workSpace: context.workSpace,
            secondaryTitle: context.featureCloseTitle,
            secondaryAction: context.featureCloseAction,
            primaryAction: context.advance
        )
    }

    func featureTabsPage() -> some View {
        MobileOnboardingTabsFeaturePage(
            workSpace: context.workSpace,
            secondaryTitle: context.featureCloseTitle,
            secondaryAction: context.featureCloseAction,
            primaryAction: context.advance
        )
    }

    func featureSyncPage() -> some View {
        MobileOnboardingSyncFeaturePage(
            secondaryTitle: context.featureCloseTitle,
            secondaryAction: context.featureCloseAction,
            primaryAction: context.advance
        )
    }

    func importBrowserPage() -> some View {
        MobileOnboardingMacImportPage(
            close: context.close,
            reviewFeatures: context.reviewFeatures
        )
    }

    /// A phone never reaches the look step; setup on it starts from Crest's own look.
    func lookPage() -> some View { EmptyView() }

    /// Touch setup has no page for reviewing an import.
    func reviewPage() -> some View { EmptyView() }

    func manualSetupPage() -> some View {
        BrowserSpaceSetupWizard(
            setup: context.setup,
            selectedSpaceID: context.selectedSpaceID,
            errorMessage: context.errorMessage,
            opensGettingStarted: context.opensGettingStarted,
            back: context.setupSecondaryAction,
            finish: context.finish
        )
    }

    /// Touch setup has no completion page.
    func completePage() -> some View { EmptyView() }
}
