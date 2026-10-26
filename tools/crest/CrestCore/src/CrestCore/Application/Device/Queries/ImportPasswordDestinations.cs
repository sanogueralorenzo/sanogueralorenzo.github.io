using CrestCore.Application;

namespace CrestCore.Contracts;

/// The Spaces each of `Passwords` goes to once the review setup holds for
/// `WorkspaceId` is imported: the destination of each reviewed Space that
/// brings its passwords and that the password belongs with. A Space that is
/// gone or locked takes none. Throws `Rejected` with `NoSetup` when setup
/// holds no review for the workspace.
[MessageLimit(64 * 1024 * 1024)]
public sealed record ImportPasswordDestinations(Guid WorkspaceId, IReadOnlyList<ImportPasswordSource> Passwords)
    : Query<ImportPasswordRoutes> {
    #region Actions - Answering

    /// Where each of the query's passwords goes once the review setup holds
    /// for its workspace is imported, leaving out Spaces that are gone or
    /// locked. Throws `Rejected` with `NoSetup` when setup holds no review for
    /// the workspace.
    internal override ImportPasswordRoutes Answer(CrestApp app) {
        var review = app.Device.ImportReview(WorkspaceId) ?? throw new Rejected(new NoSetup());
        var authority = app.Device.Workspace(WorkspaceId);
        return review.PasswordRoutes(Passwords, authority.Current, authority.IsLocked);
    }

    #endregion
}
