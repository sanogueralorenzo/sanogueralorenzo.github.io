namespace CrestCore.Contracts;

public abstract record ImportWorkspace(Guid WorkspaceId, Guid WindowId) : SessionIntent(WorkspaceId) {
    #region Variables

    /// An import brings Spaces whole, so its session is checked whole.
    internal sealed override bool ValidatesWholeSession => true;

    #endregion
}
