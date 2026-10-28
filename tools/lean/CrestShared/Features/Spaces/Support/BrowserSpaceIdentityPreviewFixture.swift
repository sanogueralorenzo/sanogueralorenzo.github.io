import Foundation

@MainActor
enum BrowserSpaceIdentityPreviewFixture {
    static let simpleSpace = SpaceModel.detached(SessionState.Seed.preview.spaces[0])
    static let secondSpace = SpaceModel.detached(SessionState.Seed.preview.spaces[1])
}
