import SwiftUI

/// The bindings a settings pane needs to edit one Space, written once.
///
/// Each binding reads the Space's settings from the core's read model and
/// writes the whole record back through the Space's existing intent, filled
/// from what the read model holds at the moment of the write. A Space that is
/// gone reads as its last published settings and writes nothing the core
/// accepts.
extension BrowserStore {
    // MARK: - Actions - Selection

    /// The Space a pane should be showing, given what it is showing now.
    ///
    /// A pane holds its own `UUID?` because "no Space yet" is a real state while a
    /// pane is appearing. This answers the only question a pane asks about it: is
    /// that still a Space, and if not, which one now?
    func repairedSpaceSelection(_ selection: UUID?) -> UUID? {
        guard let selection, spaceModel(selection) != nil else {
            return selectedSpaceID
        }
        return selection
    }

    // MARK: - Actions - Bindings

    /// A Space's name. Writing routes through `updateSpaceIdentity`, which is
    /// the only door into a Space's name, symbol, and accent.
    func spaceNameBinding(in space: SpaceModel) -> Binding<String> {
        Binding {
            space.settings.name
        } set: { [self] name in
            updateSpaceIdentity(
                space.id, name: name, symbol: space.settings.symbol, accent: space.settings.accent)
        }
    }

    /// A Space's symbol, through the same door as its name.
    func spaceSymbolBinding(in space: SpaceModel) -> Binding<String> {
        Binding {
            space.settings.symbol
        } set: { [self] symbol in
            updateSpaceIdentity(
                space.id, name: space.settings.name, symbol: symbol, accent: space.settings.accent)
        }
    }

    /// One field of a Space's browsing preferences — its search provider, its
    /// current-tab cleanup policy, its content-blocking policy.
    func browsingPreferenceBinding<Value>(
        _ keyPath: WritableKeyPath<BrowsingPreferences, Value>,
        in space: SpaceModel
    ) -> Binding<Value> {
        Binding {
            space.settings.browsingPreferences[keyPath: keyPath]
        } set: { [self] value in
            var preferences = space.settings.browsingPreferences
            preferences[keyPath: keyPath] = value
            updateBrowsingPreferences(preferences, in: space.id)
        }
    }

    /// The same, addressed by identifier, for panes whose Space selection is an
    /// optional they resolve per read — Privacy asks for a policy before it is sure
    /// it has a Space.
    func browsingPreferenceBinding<Value>(
        _ keyPath: WritableKeyPath<BrowsingPreferences, Value>,
        in spaceID: UUID?,
        default defaultValue: Value
    ) -> Binding<Value> {
        Binding { [self] in
            guard let spaceID, let space = spaceModel(spaceID) else { return defaultValue }
            return space.settings.browsingPreferences[keyPath: keyPath]
        } set: { [self] value in
            guard let spaceID, let space = spaceModel(spaceID) else { return }
            var preferences = space.settings.browsingPreferences
            preferences[keyPath: keyPath] = value
            updateBrowsingPreferences(preferences, in: spaceID)
        }
    }

    /// One field of a Space's credential preferences. Synchronization is *not*
    /// written through here: turning iCloud Keychain on or off rewrites existing
    /// items and can fail, so it goes through ``BrowserCredentialSpaceStore``.
    func credentialPreferenceBinding<Value>(
        _ keyPath: WritableKeyPath<CredentialPreferences, Value>,
        in space: SpaceModel
    ) -> Binding<Value> {
        Binding {
            space.settings.credentialPreferences[keyPath: keyPath]
        } set: { [self] value in
            var preferences = space.settings.credentialPreferences
            preferences[keyPath: keyPath] = value
            updateCredentialPreferences(preferences, in: space.id)
        }
    }

    /// A Space's branding, which is edited as a whole value rather than field by
    /// field because the branding editor composes it.
    func spaceBrandingBinding(in space: SpaceModel) -> Binding<SpaceBranding> {
        Binding {
            space.settings.look
        } set: { [self] branding in
            updateSpaceBranding(branding, in: space.id)
        }
    }

    /// The Space a pane defaults to, for preferences that always resolve to one.
    func defaultSpaceBinding() -> Binding<UUID> {
        Binding { [self] in
            workspaceModel?.defaultSpaceID ?? selectedSpaceID
        } set: { [self] spaceID in
            setDefaultSpace(spaceID)
        }
    }
}
