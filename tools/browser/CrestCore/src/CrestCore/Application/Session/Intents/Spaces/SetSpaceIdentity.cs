using CrestCore.Application;
using CrestCore.Domain;

namespace CrestCore.Contracts;

/// Renames a Space and sets its symbol and accent. A blank name reads as
/// "Untitled Space", and a blank symbol as the default one.
public sealed record SetSpaceIdentity(Guid WorkspaceId, Guid SpaceId, string Name, string Symbol, SpaceAccent Accent)
    : SessionIntent(WorkspaceId) {
    #region Actions - Session

    internal override SessionEdit? Edit(NativeSessionAuthority workspace, SessionTurn turn) {
        workspace.RequireOwnedSpaces();
        var space = workspace.Editable(turn.Basis, SpaceId);
        var name = SpaceCustomization.Chosen(Name);
        return workspace.SettingSpace(turn.Basis, space, settings => settings with {
            Name = name,
            Symbol = SpaceCustomization.ResolvedSymbol(Symbol),
            Accent = Accent
        }, SyncStaging.Edit);
    }

    #endregion
}
