import SwiftUI

struct MobileOnboardingPageContext {
    let step: SetupStep
    let welcomeAction: BrowserOnboardingWelcomeAction
    let welcomePrimaryTitle: String
    let welcomeStatus: String
    let previewWidth: CGFloat
    let personalSpace: SpaceModel
    let workSpace: SpaceModel
    let featureCloseTitle: String?
    let featureCloseAction: (() -> Void)?
    let setup: BrowserManualSetupModel
    let selectedSpaceID: Binding<UUID?>
    let errorMessage: String?
    var opensGettingStarted = false
    let welcomePrimaryAction: () -> Void
    let welcomeSetupWithoutCloudAction: () -> Void
    let advance: () -> Void
    let setupSecondaryAction: () -> Void
    let finish: () -> Void
    let close: () -> Void
    let reviewFeatures: () -> Void
}
