using CrestCore.Application;

namespace CrestCore.Contracts;

/// Imports the review setup holds for the workspace, as its choices say. An
/// included Space becomes a new Space or joins the existing one it names,
/// taking the name and look the review gives it, with the tabs the review
/// includes in the placements it chose and the saved folders those tabs need;
/// a folder matches one the destination holds by title. Pinned tabs past a
/// destination's limit become saved tabs in an `Imported Pinned Tabs` folder.
/// A new Space keeps its archive and history. Over a first launch's
/// disposable Spaces, the reviewed Spaces replace them.
///
/// Refused with `NoSetup` when setup holds no review for the workspace, and
/// `NoIncludedSpaces` when the review includes none.
public sealed record ImportReviewedSpaces(Guid WorkspaceId, Guid WindowId) : ImportWorkspace(WorkspaceId, WindowId) {
    #region Actions - Session

    /// Imports the review setup holds for this workspace; see
    /// `ImportReviewedSpaces`.
    internal override SessionEdit? Edit(NativeSessionAuthority workspace, SessionTurn turn) {
        if (!workspace.Kind.KeepsAppPreferences) throw new Rejected(new PersistentWorkspaceRequired(workspace.WorkspaceId));
        var review = workspace.Device?.ImportReview(workspace.WorkspaceId) ?? throw new Rejected(new NoSetup());
        return workspace.Importing(turn.Basis, this, [.. review.Spaces.Select(space => space.Source)], turn.Previewed, turn.Now, turn.Ids,
            import => import.ImportReviewed(review.Spaces, turn.Ids));
    }

    #endregion
}
