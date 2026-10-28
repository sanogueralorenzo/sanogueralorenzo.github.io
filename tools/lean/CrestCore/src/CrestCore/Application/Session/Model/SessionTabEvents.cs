using CrestCore.Contracts;

namespace CrestCore.Application;

internal sealed record SessionTabCopy(Guid Source, Guid Copy) {
    #region Actions - Publishing

    public TabCopied Copied(Guid workspaceId) => new(workspaceId, Source, Copy);

    #endregion
}

/// A tab's image: when `Adopts`, the one `PageId` reported, or with no page
/// the one the command's issuer offered; otherwise none.
internal sealed record SessionFaviconUpdate(Guid TabId, bool Adopts, Guid? PageId = null) {
    #region Actions - Publishing

    public TabFaviconAssigned Assigned(Guid workspaceId) => new(workspaceId, TabId, Adopts, PageId);

    #endregion
}

/// A saved or pinned tab put its page away as window `WindowId` asked,
/// keeping what brings it back unless it returned to its saved address.
internal sealed record SessionPagePutAway(Guid WindowId, Guid SpaceId, Guid TabId, bool KeepsState) {
    #region Actions - Publishing

    public TabPagePutAway PutAway(Guid workspaceId) => new(workspaceId, WindowId, SpaceId, TabId, KeepsState);

    #endregion
}

/// The tabs a command copied, the image it assigned, the transient page it
/// kept as a tab, the tabs an import placed from its Spaces and the page a
/// saved or pinned tab put away, which comparing the sessions before and
/// after it cannot tell.
internal sealed record SessionTabEvents(IReadOnlyList<SessionTabCopy> Copies, SessionFaviconUpdate? Favicon,
    IReadOnlyList<ImportedTab>? Imported = null,
    SessionPagePutAway? PutAway = null) {
    #region Static Variables

    public static SessionTabEvents None { get; } = new([], null);

    #endregion

    #region Actions - Publishing

    /// The changes that tell a reader of `workspaceId` what happened.
    public IEnumerable<Change> Changes(Guid workspaceId) =>
        Copies.Select(copy => (Change)copy.Copied(workspaceId))
            .Concat(Favicon is { } favicon ? [favicon.Assigned(workspaceId)] : [])
            .Concat(Imported is { Count: > 0 } imported ? [new TabsImported(workspaceId, imported)] : [])
            .Concat(PutAway is { } putAway ? [putAway.PutAway(workspaceId)] : []);

    #endregion
}
