import Foundation

/// The look a Space's branding started from, which its reset controls return to.
extension SpaceBranding {
    // MARK: - Variables

    /// The look of the house this branding started from, or of its scheme
    /// over its own crest and folders, or nil when it started from neither.
    var startingLook: SpaceBranding? {
        if let house = SpaceHouse.startingPoint(of: self) { return house.look }
        return SpaceScheme.startingPoint(of: self)?.applying(to: self)
    }
}
