using CrestCore.Application;
using CrestCore.Domain;

namespace CrestCore.Contracts;

/// What `Input`, as a person typed it, loads: an address as it is, or a
/// search with what `SpaceId` in `WorkspaceId` searches with. Without a
/// workspace, as a setup draft whose Spaces do not exist yet, it searches with
/// Google, opens no internal page and reads no state, so a host may ask it
/// without an app.
public sealed record ResolveAddress(Guid? WorkspaceId, Guid? SpaceId, string Input) : Query<ResolvedAddress> {
    #region Actions - Answering

    /// An address that names a workspace resolves with what the Space it names
    /// searches with, or the device's default search when it names none, and
    /// opens an internal page when the default engine shows them.
    internal override ResolvedAddress Answer(CrestApp app) {
        if (WorkspaceId is not { } workspaceId) return Unplaced();
        var provider = SpaceId is { } spaceId ? app.Device.Workspace(workspaceId).Searches(spaceId) : app.Device.SearchCatalog.Default;
        return NativeSessionAuthority.Resolved(Input, provider, app.Pages.OpensInternalPages);
    }

    /// What the address resolves to outside any workspace: Google searches
    /// what is not an address, and no internal page opens.
    internal ResolvedAddress Unplaced() => NativeSessionAuthority.Resolved(Input,
        SearchCatalog.Starting(language: null, region: null).Default, allowsInternalPages: false);

    /// An address that names no workspace resolves by the default rules
    /// without an app; one that names a workspace only an app answers.
    internal override ResolvedAddress AnswerWithoutApp(StandaloneContext context) =>
        WorkspaceId is null ? Unplaced() : base.AnswerWithoutApp(context);

    #endregion
}
