#if DEBUG
    import Foundation

    extension WorkspaceModel {
        /// The session this workspace holds now, as a seed. The read model
        /// keeps no disposable seed's marker, so the seed carries none.
        var sessionSeed: SessionState.Seed {
            SessionState.Seed(
                spaces: spaces.models.map(\.value.seed), defaultSpaceID: defaultSpaceID, disposableSeedMarker: nil,
                spaceDeletions: spaceDeletions, appPreferences: appPreferences)
        }
    }
#endif
