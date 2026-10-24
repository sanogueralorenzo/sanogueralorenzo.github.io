using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

public sealed partial class NativeSessionAuthority {
    #region Types

    /// A selection intent's work: the Space its window shows, that Space's
    /// organization the intent edits, the selection resolved there, and what
    /// the window shows next.
    internal sealed record SelectionEdit(SpaceState Space, BrowserTabCollection Edited, ResolvedSelection Selected, WindowFollowUp FollowUp) {
        #region Variables

        /// The tab the window shows in the Space, or null for none.
        public Guid? Shown => FollowUp.Window?.Tab(Space.Id);

        #endregion

        #region Actions - Following

        /// The tab the window shows once the edit takes its shown tab away: the
        /// one it showed before, among the tabs the selection leaves; null when
        /// the shown tab stays or nothing qualifies.
        public Guid? Fallback() => Shown is { } shown && Selected.Holds(shown)
            ? FollowUp.FallbackAfterDismissing(Space.Id, shown, Space.Tabs.Select(tab => tab.Id).Where(id => !Selected.Holds(id)).ToHashSet())
            : null;

        /// The session with the edited organization, staged as `staging`, with
        /// what the window shows next and what the edit did that the states
        /// cannot tell. Split metadata no tab uses goes with the edit.
        public SessionEdit Result(SessionState basis, SyncStaging staging, SessionTabEvents? events = null,
            params SpaceState[] alsoEdited) {
            Edited.PruneSplitMetadata();
            return new(Replacing(basis, [Edited.Capture(Space), .. alsoEdited]), staging, FollowUp, events);
        }

        #endregion
    }

    #endregion

    #region Actions - Selections

    /// The work of an intent on a selection made in `windowId`'s sidebar: the
    /// Space must be the one the window shows, and the selection must hold
    /// what the window saw, or it is refused with `SelectionChanged`.
    internal SelectionEdit Selecting(SessionState basis, Guid windowId, Guid spaceId, TabSelection selection) {
        var followUp = new WindowFollowUp(IssuingWindow(windowId));
        if (followUp.Window?.ShownSpaceId != spaceId) throw new Rejected(new SelectionChanged());
        var space = Editable(basis, spaceId);
        var edited = BrowserTabCollection.Restore(space);
        return new(space, edited, edited.Select(selection), followUp);
    }

    /// Copies of tabs start from where their sources' pages are now, preferring
    /// the pages `windowId` shows; see `StartFromSourcePage`. Answers what the
    /// copies publish.
    internal SessionTabEvents StartingCopies(SelectionEdit batch, IReadOnlyList<(Guid Source, Guid Copy)> copies, Guid windowId,
        Pages? pages) {
        foreach (var (source, copy) in copies) StartFromSourcePage(batch.Edited.Tab(copy), source, windowId, pages);
        return new([.. copies.Select(pair => new SessionTabCopy(pair.Source, pair.Copy))], null);
    }

    #endregion
}
