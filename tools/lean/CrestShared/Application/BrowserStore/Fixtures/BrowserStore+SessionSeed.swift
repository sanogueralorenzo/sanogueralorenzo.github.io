#if DEBUG
    import Foundation

    extension BrowserStore {
        /// The session this window's workspace holds now, as the seed another
        /// window's workspace would open from, for tests that carry what one
        /// store did into the next or compare it with what it held before or
        /// with what a session file holds.
        var sessionSeed: SessionState.Seed {
            workspaceModel?.sessionSeed ?? SessionState.Seed(spaces: [])
        }

        /// Every tab this window's workspace holds open, Space by Space.
        var openTabIDs: [UUID] {
            spaceModels.flatMap { $0.tabs.models.map(\.id) }
        }
    }
#endif
