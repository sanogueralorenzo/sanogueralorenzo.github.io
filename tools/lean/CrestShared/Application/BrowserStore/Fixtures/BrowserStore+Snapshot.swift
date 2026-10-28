#if DEBUG
    import Foundation

    extension BrowserStore {
        /// The session of this window's workspace as the read model holds it
        /// now, for tests to read values from. A workspace the device no
        /// longer holds reads as an empty session. The read model keeps only
        /// whether the session is still the disposable first-install seed, so
        /// a seed's marker reads as the workspace's identity.
        var snapshot: SessionState {
            guard let workspace = core.state.workspaces[family.workspaceID] else {
                return SessionState(
                    spaces: [], disposableSeedMarker: nil, spaceDeletions: [],
                    appPreferences: nil)
            }
            return SessionState(
                spaces: workspace.spaces.values, disposableSeedMarker: workspace.isDisposableSeed ? workspace.id : nil,
                spaceDeletions: workspace.spaceDeletions, appPreferences: workspace.appPreferences)
        }
    }
#endif
