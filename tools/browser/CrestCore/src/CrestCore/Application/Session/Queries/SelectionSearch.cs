using CrestCore.Application;
using CrestCore.Domain;

namespace CrestCore.Contracts;

/// The search for text a person selected on a page of `SpaceId`, with what
/// the Space searches with.
public sealed record SelectionSearch(Guid WorkspaceId, Guid SpaceId, string Text) : Query<SelectionSearchAnswer> {
    #region Actions - Answering

    internal override SelectionSearchAnswer Answer(CrestApp app) => Answer(app.Device.Workspace(WorkspaceId));

    /// The search for selected text with the Space's provider, when the text
    /// is not blank and the results address is one Crest opens from a page.
    private SelectionSearchAnswer Answer(NativeSessionAuthority workspace) {
        var engine = workspace.Searches(SpaceId);
        string text = Text.Trim();
        if (text.Length == 0) return new(Url: null, engine.Title);
        string url = engine.Search(text);
        bool opens = Uri.TryCreate(url, UriKind.Absolute, out var parsed) && new ExternalWebLink(parsed.Scheme, parsed.Host).IsAccepted;
        return new(opens ? url : null, engine.Title);
    }

    #endregion
}
