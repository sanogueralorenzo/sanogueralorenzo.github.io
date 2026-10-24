import SwiftUI

extension SetupStep {
    /// The page `pages` shows for the step.
    @MainActor @ViewBuilder
    func page(in pages: some BrowserOnboardingPages) -> some View {
        switch kind {
        case .welcome: pages.welcomePage()
        case .look: pages.lookPage()
        case .featureSpaces: pages.featureSpacesPage()
        case .featureTabs: pages.featureTabsPage()
        case .featureSync: pages.featureSyncPage()
        case .importBrowser: pages.importBrowserPage()
        case .review: pages.reviewPage()
        case .manualSetup: pages.manualSetupPage()
        case .complete: pages.completePage()
        }
    }
}
