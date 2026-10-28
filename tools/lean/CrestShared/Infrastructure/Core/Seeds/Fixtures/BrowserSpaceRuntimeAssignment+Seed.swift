#if DEBUG
    import Foundation

    extension BrowserSpaceRuntimeAssignment {
        // MARK: - Initializers

        /// Where a seeded Space lives: its identity and profile.
        init(space: SpaceState.Seed) {
            self.init(spaceID: space.id, profileID: space.profileID)
        }
    }
#endif
