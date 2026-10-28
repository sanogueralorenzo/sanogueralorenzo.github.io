import Foundation

extension ImportSpaceNames {
    /// `source`'s Space names in the person's language, or nil for a source
    /// whose Spaces are named after its profiles.
    init?(resolving source: ImportSource) {
        guard let spaceName = source.spaceName, let numberedSpaceName = source.numberedSpaceName else { return nil }
        self.init(
            source: source, spaceName: String(localized: spaceName),
            numberedSpaceName: String(localized: numberedSpaceName))
    }
}
