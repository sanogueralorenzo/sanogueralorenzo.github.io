import SwiftUI

/// The pages a platform shows for the steps of setup, one method per step.
/// `SetupStep.page(in:)` picks the step's page, so a step the core adds fails
/// to compile until every platform says what it shows there. A platform that
/// never reaches a step shows nothing for it.
@MainActor
protocol BrowserOnboardingPages {
    associatedtype WelcomePage: View
    associatedtype LookPage: View
    associatedtype FeatureSpacesPage: View
    associatedtype FeatureTabsPage: View
    associatedtype FeatureSyncPage: View
    associatedtype ImportBrowserPage: View
    associatedtype ReviewPage: View
    associatedtype ManualSetupPage: View
    associatedtype CompletePage: View

    func welcomePage() -> WelcomePage
    func lookPage() -> LookPage
    func featureSpacesPage() -> FeatureSpacesPage
    func featureTabsPage() -> FeatureTabsPage
    func featureSyncPage() -> FeatureSyncPage
    func importBrowserPage() -> ImportBrowserPage
    func reviewPage() -> ReviewPage
    func manualSetupPage() -> ManualSetupPage
    func completePage() -> CompletePage
}
