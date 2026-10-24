import Foundation

/// The Spaces the feature pages draw: the preview session's, as the core
/// resolves them, held by no workspace.
@MainActor
enum MobileOnboardingPreviewFixtures {
    // MARK: - Static Variables

    static var tutorialWorkSpace: SpaceModel { SpaceModel.previewSpaces[0] }
    static var tutorialPersonalSpace: SpaceModel { SpaceModel.previewSpaces[1] }
}
