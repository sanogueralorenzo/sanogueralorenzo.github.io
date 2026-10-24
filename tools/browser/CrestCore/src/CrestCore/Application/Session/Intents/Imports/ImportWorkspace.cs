namespace CrestCore.Contracts;

/// Brings Spaces into the persistent workspace: a file's Spaces
/// (`ImportSpaces`), imported Spaces a person reviewed
/// (`ImportReviewedSpaces`) or the Spaces of the manual setup the device holds
/// (`ApplyManualSetup`). The choices about them are typed and name each Space
/// by its identity. An import is saved with its sync journal before it
/// returns.
///
/// Folder and history records keep their identities unless another Space
/// already holds them, because those identities are global in sync. A Space,
/// profile or tab that collides with another takes a new identity: each
/// imported tab is published in `TabsImported` with the tab it came from, and
/// each of the workspace's own tabs that took a new identity as `TabCopied`.
/// The window `WindowId` shows the first Space the import brought or changed.
///
/// Refused with `PersistentWorkspaceRequired` for any other workspace,
/// `SpaceLocked` when it would change a locked Space, giving it tabs or
/// folders or another name or look, `InvalidImport` for Spaces or choices it
/// cannot read, `SpaceLimitReached` when the workspace would hold too many
/// Spaces, and `SpaceBeingDeleted` when a Space it names is going away. A
/// locked Space the import leaves as it was, such as one a review leaves out,
/// a draft left unchanged or one it only moves in the order, never refuses it.
public abstract record ImportWorkspace(Guid WorkspaceId, Guid WindowId) : SessionIntent(WorkspaceId) {
    #region Variables

    /// An import brings Spaces whole, so its session is checked whole.
    internal sealed override bool ValidatesWholeSession => true;

    #endregion
}
